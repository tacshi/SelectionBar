import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "SelectionMonitor")

/// Monitors global text selection and reports selected text via callback.
/// Uses Accessibility API to query selected text.
@MainActor
public final class SelectionMonitor {
  // MARK: - Public Properties

  /// Called when text is selected in another app
  public var onTextSelected: ((_ text: String, _ mouseLocation: NSPoint) -> Void)?

  /// Called when the selection bar should be dismissed
  public var onDismissRequested: (() -> Void)?

  /// Minimum character count to trigger the selection bar
  public var minimumCharacterCount: Int = 3

  /// Bundle IDs of apps where the selection bar should not appear
  public var ignoredBundleIDs: Set<String> = []

  /// Whether text selection should only trigger while modifier key is held.
  public var requireActivationModifier: Bool = false

  /// Required modifier key when `requireActivationModifier` is enabled.
  public var requiredActivationModifier: SelectionBarActivationModifier = .option

  // MARK: - Private Properties

  /// Event monitors — marked nonisolated(unsafe) to allow cleanup in deinit.
  nonisolated(unsafe) private var mouseUpMonitor: Any?
  nonisolated(unsafe) private var mouseDownMonitor: Any?
  nonisolated(unsafe) private var keyDownMonitor: Any?
  nonisolated(unsafe) private var appSwitchObserver: NSObjectProtocol?
  private let accessibility = SelectionMonitorAccessibility()
  private let clipboardFallback = SelectionMonitorClipboardFallback()

  private var debounceTask: Task<Void, Never>?
  private var isEnabled = false

  /// Track mouse-down location to detect drag vs click
  private var mouseDownLocation: NSPoint?

  /// Track click count for mouse-down/up sequence (2+ means double/triple click selection)
  private var mouseDownClickCount: Int = 1

  /// Focused window origin at mouse-down to detect real window drags.
  private var mouseDownWindowOrigin: CGPoint?
  private var mouseDownWindowPID: pid_t?

  /// Minimum drag distance (in points) to consider it a text selection gesture
  private let dragThreshold: CGFloat = 5

  /// File browser contexts where a double-click is usually an open action, not text selection.
  private static let fileBrowserBundleIDs: Set<String> = [
    "com.apple.finder",
    "com.apple.appkit.xpc.openAndSavePanelService",
  ]

  // MARK: - Lifecycle

  public init() {}

  deinit {
    if let monitor = mouseUpMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = mouseDownMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = keyDownMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let observer = appSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  // MARK: - Public Methods

  public func start() {
    guard !isEnabled else {
      logger.info("SelectionMonitor already enabled, skipping start")
      return
    }
    isEnabled = true

    let trusted = checkAccessibilityPermission(promptIfNeeded: false)
    logger.info(
      "SelectionMonitor starting — AX trusted: \(trusted, privacy: .public)"
    )

    setupMonitors()
    logger.info(
      "SelectionMonitor started — mouseUp: \(self.mouseUpMonitor != nil, privacy: .public), mouseDown: \(self.mouseDownMonitor != nil, privacy: .public)"
    )
  }

  /// Checks Accessibility permission and optionally requests it from the user.
  @discardableResult
  public func checkAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
    accessibility.checkAccessibilityPermission(promptIfNeeded: promptIfNeeded)
  }

  /// Returns whether the currently focused element is editable.
  /// This is used by UI flow to decide whether "Apply" should be shown.
  public func isFocusedElementEditable() -> Bool {
    accessibility.isFocusedElementEditable()
  }

  public func stop() {
    guard isEnabled else { return }
    isEnabled = false
    removeMonitors()
    debounceTask?.cancel()
    debounceTask = nil
    logger.info("SelectionMonitor stopped")
  }

  // MARK: - Private Methods

  private func setupMonitors() {
    requestListenEventAccessIfNeeded()

    // Monitor mouse down — track position + dismiss existing bar
    mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
      [weak self] event in
      let location = NSEvent.mouseLocation
      Task { @MainActor in
        self?.mouseDownLocation = location
        self?.mouseDownClickCount = max(event.clickCount, 1)
        self?.captureMouseDownWindowOrigin()
        self?.onDismissRequested?()
      }
    }

    // Monitor mouse up — detect selection
    mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
      [weak self] event in
      let location = NSEvent.mouseLocation
      let clickCount = max(event.clickCount, 1)
      let modifierFlags = event.modifierFlags
      Task { @MainActor in
        self?.handleMouseUp(
          at: location,
          clickCount: clickCount,
          modifierFlags: modifierFlags
        )
      }
    }

    // Monitor escape key (dismiss)
    keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      let isEscape = event.keyCode == 53  // Escape
      let isSelectAll = Self.isSelectAllShortcut(event)

      if isEscape {
        Task { @MainActor in
          self?.onDismissRequested?()
        }
        return
      }

      if isSelectAll {
        Task { @MainActor in
          self?.handleSelectAllShortcut(modifierFlags: event.modifierFlags)
        }
      }
    }

    // Monitor app switch (dismiss)
    appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.onDismissRequested?()
      }
    }
  }

  private func removeMonitors() {
    if let monitor = mouseUpMonitor {
      NSEvent.removeMonitor(monitor)
      mouseUpMonitor = nil
    }
    if let monitor = mouseDownMonitor {
      NSEvent.removeMonitor(monitor)
      mouseDownMonitor = nil
    }
    if let monitor = keyDownMonitor {
      NSEvent.removeMonitor(monitor)
      keyDownMonitor = nil
    }
    if let observer = appSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appSwitchObserver = nil
    }
  }

  /// Compute distance between two points
  private func distance(from a: NSPoint, to b: NSPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    return sqrt(dx * dx + dy * dy)
  }

  private func handleMouseUp(
    at mouseLocation: NSPoint,
    clickCount: Int,
    modifierFlags: NSEvent.ModifierFlags
  ) {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

    // Skip if VoiceTale is the frontmost app
    if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
      return
    }

    // Skip ignored apps (e.g. terminals where paste goes to prompt, not selection)
    if let bundleID = frontApp.bundleIdentifier,
      ignoredBundleIDs.contains(bundleID)
    {
      return
    }

    // Ignore gestures inside SelectionBar's own UI (e.g. result window text selection).
    if accessibility.isCurrentProcessElement(at: mouseLocation) {
      logger.debug("Ignoring selection gesture in SelectionBar UI")
      return
    }

    if !isRequiredActivationModifierPressed(in: modifierFlags) {
      logger.debug("Ignoring selection gesture without required activation modifier")
      return
    }

    // Determine if this was a drag selection or multi-click selection.
    let wasDrag: Bool
    if let downLocation = mouseDownLocation {
      wasDrag = distance(from: downLocation, to: mouseLocation) >= dragThreshold
    } else {
      wasDrag = false
    }
    let effectiveClickCount = max(clickCount, mouseDownClickCount)
    let isSelectionGesture = wasDrag || effectiveClickCount >= 2
    let isMultiClickGesture = effectiveClickCount >= 2
    let didMoveWindow = focusedWindowMovedSinceMouseDown(forPID: frontApp.processIdentifier)
    mouseDownLocation = nil
    mouseDownClickCount = 1
    clearMouseDownWindowOrigin()

    // Only react to explicit selection gestures (drag, double-click, triple-click).
    // This prevents stale selections from re-triggering when windows regain focus
    // and the user performs a plain single click.
    guard isSelectionGesture else {
      logger.debug("Ignoring non-selection mouse up event")
      return
    }

    if shouldIgnoreMultiClickSelection(
      frontmostBundleID: frontApp.bundleIdentifier,
      clickCount: effectiveClickCount
    ) {
      // Preserve multi-click text selection in editable controls (e.g. filename/search fields)
      // even inside Finder/open-save panel contexts.
      if accessibility.isFocusedElementEditable() {
        logger.debug("Allowing multi-click selection in editable field")
      } else {
        logger.debug("Ignoring multi-click selection in file browser context")
        return
      }
    }

    // Debounce: wait 200ms for selection to settle
    debounceTask?.cancel()
    debounceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      await self?.querySelectedText(
        at: mouseLocation,
        isSelectionGesture: isSelectionGesture,
        isMultiClickGesture: isMultiClickGesture,
        didMoveWindow: didMoveWindow
      )
    }
  }

  private func shouldIgnoreMultiClickSelection(frontmostBundleID: String?, clickCount: Int)
    -> Bool
  {
    guard clickCount >= 2, let bundleID = frontmostBundleID else { return false }
    return Self.fileBrowserBundleIDs.contains(bundleID)
  }

  private func handleSelectAllShortcut(modifierFlags: NSEvent.ModifierFlags) {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

    if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
      return
    }

    if let bundleID = frontApp.bundleIdentifier,
      ignoredBundleIDs.contains(bundleID)
    {
      return
    }

    // Ignore Cmd+A inside SelectionBar UI editors/result views.
    if accessibility.isFocusedElementOwnedByCurrentProcess() {
      logger.debug("Ignoring Cmd+A in SelectionBar UI")
      return
    }

    guard accessibility.isFocusedTextContext() else {
      logger.debug("Ignoring Cmd+A outside text context")
      return
    }

    if !isRequiredActivationModifierPressed(in: modifierFlags) {
      logger.debug("Ignoring Cmd+A without required activation modifier")
      return
    }

    onDismissRequested?()

    debounceTask?.cancel()
    let mouseLocation = NSEvent.mouseLocation
    debounceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      await self?.querySelectedText(
        at: mouseLocation,
        isSelectionGesture: true,
        isMultiClickGesture: true,
        didMoveWindow: false
      )
    }
  }

  private func querySelectedText(
    at mouseLocation: NSPoint,
    isSelectionGesture: Bool,
    isMultiClickGesture: Bool,
    didMoveWindow: Bool
  ) async {
    guard isEnabled else { return }

    guard AXIsProcessTrusted() else {
      logger.warning("Accessibility not trusted, cannot query selected text")
      return
    }

    // Prevent recursive triggers from SelectionBar-owned UI.
    if accessibility.isFocusedElementOwnedByCurrentProcess() {
      logger.debug("Skipping selection query for SelectionBar-owned focused element")
      return
    }

    // Strategy 1: AX query for selected text on focused element
    if let text = queryViaAccessibility(isSelectionGesture: isSelectionGesture) {
      logger.info("AX selected text (\(text.count) chars)")
      onTextSelected?(text, mouseLocation)
      return
    }

    // Strategy 2: Clipboard fallback (drag-select or double/triple-click selection)
    guard isSelectionGesture else {
      return
    }

    // Avoid synthetic Cmd+C on non-text drag gestures.
    // Dragging windows/titlebars in many apps would otherwise produce system beeps.
    if !isMultiClickGesture {
      if didMoveWindow {
        logger.debug(
          "Skipping clipboard fallback: focused window moved during drag gesture")
        return
      }
      // Text-context detection relies on the same AX tree that already
      // failed to return selected text (Strategy 1). Apps like WeChat,
      // WhatsApp, and Telegram often don't expose text context reliably,
      // so we don't gate the clipboard fallback on it — the didMoveWindow
      // check and drag threshold are sufficient to filter false positives.
    }

    logger.debug("AX query failed, trying clipboard fallback")
    if let text = await queryViaClipboard(isSelectionGesture: isSelectionGesture) {
      logger.info("Clipboard selected text (\(text.count) chars)")
      onTextSelected?(text, mouseLocation)
    }
  }

  /// Query selected text via Accessibility API (fast, non-invasive, works for native apps).
  /// Returns nil if the focused element has no selected text.
  private func queryViaAccessibility(isSelectionGesture: Bool) -> String? {
    guard let text = accessibility.selectedTextFromFocusedHierarchy() else { return nil }
    guard
      text.count
        >= effectiveMinimumCharacterCount(
          for: text,
          isSelectionGesture: isSelectionGesture
        )
    else { return nil }
    return text
  }

  private func effectiveMinimumCharacterCount(for text: String, isSelectionGesture: Bool) -> Int {
    // Ideographic (Han) words are commonly 1-2 chars on double-click selection,
    // so use a lower threshold to avoid missing those selections.
    if text.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
      return 1
    }
    // Intentional selection gestures (double-click/drag) should allow short Latin words like "Ok".
    if isSelectionGesture {
      return 2
    }
    return minimumCharacterCount
  }

  private static func isSelectAllShortcut(_ event: NSEvent) -> Bool {
    guard event.keyCode == 0 else { return false }  // A
    guard !event.isARepeat else { return false }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command) else { return false }

    if flags.contains(.shift)
      || flags.contains(.control)
      || flags.contains(.option)
      || flags.contains(.function)
    {
      return false
    }

    return true
  }

  private func isRequiredActivationModifierPressed(in flags: NSEvent.ModifierFlags) -> Bool {
    guard requireActivationModifier else { return true }
    let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
    switch requiredActivationModifier {
    case .command:
      return normalizedFlags.contains(.command)
    case .option:
      return normalizedFlags.contains(.option)
    case .control:
      return normalizedFlags.contains(.control)
    case .shift:
      return normalizedFlags.contains(.shift)
    }
  }

  /// Capture focused window origin at mouse-down.
  private func captureMouseDownWindowOrigin() {
    guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
      clearMouseDownWindowOrigin()
      return
    }
    mouseDownWindowPID = app.processIdentifier
    mouseDownWindowOrigin = accessibility.focusedWindowOrigin(forPID: app.processIdentifier)
  }

  private func clearMouseDownWindowOrigin() {
    mouseDownWindowPID = nil
    mouseDownWindowOrigin = nil
  }

  /// True when focused window origin changed between mouse-down and mouse-up.
  private func focusedWindowMovedSinceMouseDown(forPID pid: pid_t) -> Bool {
    guard mouseDownWindowPID == pid,
      let downOrigin = mouseDownWindowOrigin,
      let upOrigin = accessibility.focusedWindowOrigin(forPID: pid)
    else {
      return false
    }
    return distance(from: downOrigin, to: upOrigin) >= 1
  }

  /// Fallback: simulate Cmd+C, read clipboard, restore original clipboard contents.
  /// Used for apps where AX doesn't expose selected text reliably.
  private func queryViaClipboard(isSelectionGesture: Bool) async -> String? {
    guard let text = await clipboardFallback.selectedTextByCopyCommand() else { return nil }
    guard
      text.count
        >= effectiveMinimumCharacterCount(
          for: text,
          isSelectionGesture: isSelectionGesture
        )
    else { return nil }
    return text
  }

  // MARK: - Input Monitoring Permission

  private func requestListenEventAccessIfNeeded() {
    // Global event monitors require Input Monitoring permission on modern macOS.
    // Avoid triggering permission prompts in automated tests.
    guard !Self.isRunningUnderAutomatedTests else { return }
    guard !CGPreflightListenEventAccess() else { return }
    CGRequestListenEventAccess()
  }

  private static var isRunningUnderAutomatedTests: Bool {
    let processInfo = ProcessInfo.processInfo
    let processName = processInfo.processName.localizedLowercase
    if processName.contains("xctest") || processName.contains("swiftpm-testing-helper") {
      return true
    }

    let environment = processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil
      || environment["SWIFTPM_TESTS_MODULE"] != nil
  }
}
