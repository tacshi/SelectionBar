import AppKit
import CoreGraphics
import PermissionFlow
import SwiftUI

@MainActor
final class SelectionBarPermissionPanelController {
  private let settingsBundleIdentifier = "com.apple.systempreferences"
  private let trackingInterval: TimeInterval = 1.0 / 30.0
  private let screenInset: CGFloat = 12
  private let panelGap: CGFloat = 8
  private let sidebarWidth: CGFloat = 230
  private let panelHeight: CGFloat = 132
  private let initialSettingsWindowLookupGrace: TimeInterval = 3
  private var panel: SelectionBarPermissionPanel?
  private var trackingTimer: Timer?
  private var hasLocatedSettingsWindow = false
  private var settingsWindowLookupDeadline: Date?

  func show(pane: PermissionFlowPane, appURL: URL?) {
    close()

    let panel = SelectionBarPermissionPanel(
      paneTitle: pane.selectionBarDisplayTitle,
      appURL: appURL,
      onClose: { [weak self] in
        self?.close()
      }
    )
    self.panel = panel
    hasLocatedSettingsWindow = false
    settingsWindowLookupDeadline = Date().addingTimeInterval(initialSettingsWindowLookupGrace)

    trackingTimer = Timer.scheduledTimer(withTimeInterval: trackingInterval, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updatePanelFrame()
      }
    }
    trackingTimer?.tolerance = trackingInterval * 0.25
    updatePanelFrame()
  }

  func close() {
    trackingTimer?.invalidate()
    trackingTimer = nil
    panel?.close()
    panel = nil
    hasLocatedSettingsWindow = false
    settingsWindowLookupDeadline = nil
  }

  private func updatePanelFrame() {
    guard let panel else { return }
    guard let settingsFrame = settingsWindowFrame() else {
      if hasLocatedSettingsWindow || settingsWindowLookupDeadline.map({ Date() >= $0 }) == true {
        close()
      }
      return
    }

    hasLocatedSettingsWindow = true
    settingsWindowLookupDeadline = nil
    panel.snap(to: targetFrame(for: settingsFrame))
  }

  private func targetFrame(for settingsFrame: CGRect) -> CGRect {
    let screenFrame =
      NSScreen.screens.first(where: { $0.frame.intersects(settingsFrame) })?.visibleFrame
      ?? NSScreen.main?.visibleFrame
      ?? settingsFrame
    let contentMinX = settingsFrame.minX + min(sidebarWidth, settingsFrame.width * 0.36)
    let availableWidth = max(360, settingsFrame.maxX - contentMinX)
    let width = min(availableWidth, screenFrame.width - (screenInset * 2))

    var origin = CGPoint(
      x: contentMinX,
      y: settingsFrame.minY - panelHeight - panelGap
    )

    if origin.y < screenFrame.minY + screenInset {
      origin.y = settingsFrame.minY + panelGap
    }

    origin.x = max(
      screenFrame.minX + screenInset, min(origin.x, screenFrame.maxX - width - screenInset))
    origin.y = max(
      screenFrame.minY + screenInset, min(origin.y, screenFrame.maxY - panelHeight - screenInset))

    return CGRect(origin: origin, size: CGSize(width: width, height: panelHeight))
  }

  private func settingsWindowFrame() -> CGRect? {
    guard let settingsApp = runningSettingsApplication() else { return nil }
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return nil
    }

    return
      windows
      .filter { window in
        guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t else { return false }
        guard ownerPID == settingsApp.processIdentifier else { return false }
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
        return layer == 0 && alpha > 0
      }
      .compactMap { window -> CGRect? in
        guard let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        guard let cgFrame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        let frame = appKitFrame(fromGlobalTopLeftFrame: cgFrame)
        guard frame.width > 320, frame.height > 240 else { return nil }
        return frame
      }
      .max(by: { $0.width * $0.height < $1.width * $1.height })
  }

  private func runningSettingsApplication() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleIdentifier)
      .filter { $0.activationPolicy != .prohibited }
      .max(by: { $0.processIdentifier < $1.processIdentifier })
  }

  private func appKitFrame(fromGlobalTopLeftFrame frame: CGRect) -> CGRect {
    let screens = NSScreen.screens.compactMap { screen -> (frame: CGRect, cgBounds: CGRect)? in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
      else {
        return nil
      }

      let displayID = CGDirectDisplayID(number.uint32Value)
      return (frame: screen.frame, cgBounds: CGDisplayBounds(displayID))
    }

    let matchedScreen =
      screens
      .filter { $0.cgBounds.intersects(frame) }
      .max { lhs, rhs in
        lhs.cgBounds.intersection(frame).width * lhs.cgBounds.intersection(frame).height
          < rhs.cgBounds.intersection(frame).width * rhs.cgBounds.intersection(frame).height
      }

    guard let matchedScreen else { return frame }

    let localX = frame.minX - matchedScreen.cgBounds.minX
    let localY = frame.minY - matchedScreen.cgBounds.minY

    return CGRect(
      x: matchedScreen.frame.minX + localX,
      y: matchedScreen.frame.maxY - localY - frame.height,
      width: frame.width,
      height: frame.height
    )
  }
}

@MainActor
private final class SelectionBarPermissionPanel: NSPanel {
  private let hostingView: NSHostingView<SelectionBarPermissionPanelView>
  private var didShow = false
  private let panelHeight: CGFloat = 132

  init(paneTitle: String, appURL: URL?, onClose: @escaping @MainActor () -> Void) {
    let panelView = SelectionBarPermissionPanelView(
      paneTitle: paneTitle,
      appURL: appURL,
      onClose: onClose
    )
    hostingView = NSHostingView(rootView: panelView)

    super.init(
      contentRect: CGRect(origin: .zero, size: CGSize(width: 520, height: 132)),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .floating
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    animationBehavior = .utilityWindow
    contentView = hostingView
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func snap(to frame: CGRect) {
    setFrame(
      CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: panelHeight)),
      display: true
    )
    if !didShow {
      didShow = true
      orderFrontRegardless()
    }
  }
}

@available(macOS 13.0, *)
private struct SelectionBarPermissionPanelView: View {
  let paneTitle: String
  let appURL: URL?
  let onClose: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: "arrowshape.up.fill")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.tint)

        Text(title)
          .font(.system(size: 14))

        Spacer()

        Button(action: onClose) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.primary, .secondary.opacity(0.35))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Close Permission Helper", bundle: .localizedModule))
        .accessibilityHint(Text("Dismisses the permission helper panel", bundle: .localizedModule))
      }

      if let appURL {
        SelectionBarAppDragItemView(url: appURL)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.top, 8)
    .padding(.bottom, 12)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(.primary.opacity(0.14), lineWidth: 1)
        )
    )
  }

  private var title: AttributedString {
    let appName =
      appURL.map { FileManager.default.displayName(atPath: $0.path) }
      ?? String(localized: "SelectionBar", bundle: .localizedModule)

    // One format string rather than concatenated fragments: Japanese and
    // Chinese need a different word order than "Drag X to … allow Y."
    let format = String(
      localized: "Drag %@ to the list above to allow %@.",
      bundle: .localizedModule
    )
    var title = AttributedString(String(format: format, appName, paneTitle))
    for value in [appName, paneTitle] {
      if let range = title.range(of: value) {
        title[range].inlinePresentationIntent = .stronglyEmphasized
      }
    }
    return title
  }
}

@available(macOS 13.0, *)
private struct SelectionBarAppDragItemView: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> SelectionBarAppDragSourceView {
    SelectionBarAppDragSourceView(url: url)
  }

  func updateNSView(_ nsView: SelectionBarAppDragSourceView, context: Context) {
    nsView.update(url: url)
  }
}

@available(macOS 13.0, *)
private final class SelectionBarAppDragSourceView: NSView, NSDraggingSource {
  private var url: URL
  private let hostingView: NSHostingView<SelectionBarAppDragCardContent>
  private var mouseDownPoint: NSPoint?
  private var hasBegunDragging = false

  init(url: URL) {
    self.url = url
    hostingView = NSHostingView(rootView: SelectionBarAppDragCardContent(url: url))
    super.init(frame: .zero)

    hostingView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hostingView)

    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    let fitting = hostingView.fittingSize
    return NSSize(width: NSView.noIntrinsicMetric, height: max(56, fitting.height))
  }

  func update(url: URL) {
    self.url = url
    hostingView.rootView = SelectionBarAppDragCardContent(url: url)
    invalidateIntrinsicContentSize()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    mouseDownPoint = convert(event.locationInWindow, from: nil)
    hasBegunDragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !hasBegunDragging, let mouseDownPoint else { return }

    let currentPoint = convert(event.locationInWindow, from: nil)
    let distance = hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y)
    guard distance > 4 else { return }

    hasBegunDragging = true
    beginAppDrag(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    mouseDownPoint = nil
    hasBegunDragging = false
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
    true
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    mouseDownPoint = nil
    hasBegunDragging = false
  }

  private func beginAppDrag(with event: NSEvent) {
    let writer = SelectionBarAppBundlePasteboardWriter(url: url)
    let draggingItem = NSDraggingItem(pasteboardWriter: writer)
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icon.size = NSSize(width: 56, height: 56)
    let dragPoint = convert(event.locationInWindow, from: nil)
    let dragFrame = NSRect(
      x: dragPoint.x - 28,
      y: dragPoint.y - 28,
      width: 56,
      height: 56
    )
    draggingItem.setDraggingFrame(dragFrame, contents: icon)

    let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
    session.draggingFormation = .none
  }
}

private final class SelectionBarAppBundlePasteboardWriter: NSObject, NSPasteboardWriting {
  private let url: URL

  init(url: URL) {
    self.url = url
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    [
      .fileURL,
      .URL,
      NSPasteboard.PasteboardType("NSFilenamesPboardType"),
      NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
      .string,
    ]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
    case .fileURL, .URL, NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"):
      return url.absoluteString
    case NSPasteboard.PasteboardType("NSFilenamesPboardType"):
      return [url.path]
    case .string:
      return url.path
    default:
      return nil
    }
  }
}

@available(macOS 13.0, *)
private struct SelectionBarAppDragCardContent: View {
  let url: URL

  var body: some View {
    HStack(spacing: 10) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: 32, height: 32)
        .cornerRadius(9)

      Text(url.deletingPathExtension().lastPathComponent)
        .font(.system(size: 16))
        .foregroundStyle(.primary)

      Spacer()

      VStack(spacing: 0) {
        Image(systemName: "hand.draw")
          .font(.system(size: 14))
        Text("Drag", bundle: .localizedModule)
          .font(.system(size: 8, weight: .light))
      }
      .foregroundStyle(.secondary)
      .padding(.trailing, 6)
    }
    .padding(6)
    .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(.primary.opacity(0.085), lineWidth: 1)
    )
  }
}

extension PermissionFlowPane {
  fileprivate var selectionBarDisplayTitle: String {
    switch self {
    case .accessibility:
      return String(localized: "Accessibility", bundle: .localizedModule)
    case .inputMonitoring:
      return String(localized: "Input Monitoring", bundle: .localizedModule)
    case .appManagement:
      return String(localized: "App Management", bundle: .localizedModule)
    case .bluetooth:
      return String(localized: "Bluetooth", bundle: .localizedModule)
    case .developerTools:
      return String(localized: "Developer Tools", bundle: .localizedModule)
    case .fullDiskAccess:
      return String(localized: "Full Disk Access", bundle: .localizedModule)
    case .mediaAppleMusic:
      return String(localized: "Media & Apple Music", bundle: .localizedModule)
    case .screenRecording:
      return String(localized: "Screen Recording", bundle: .localizedModule)
    }
  }
}
