import AppKit
import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionMonitor Tests")
@MainActor
struct SelectionMonitorTests {
  @Test(
    "pressing the activation key shows an existing selection",
    arguments: SelectionBarActivationModifier.allCases)
  func activationKeyShowsExistingSelection(modifier: SelectionBarActivationModifier) async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.selectedText = "selected range"
    accessibility.focusedTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)
    monitor.requireActivationModifier = true
    monitor.requiredActivationModifier = modifier
    monitor.start()
    defer { monitor.stop() }

    var selections: [String] = []
    var locations: [NSPoint] = []
    monitor.onTextSelected = { text, location in
      selections.append(text)
      locations.append(location)
    }
    let location = NSPoint(x: 40, y: 80)
    await monitor.handleModifierFlagsChanged(
      [], at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    monitor.handleMouseDown(at: .zero, clickCount: 1)
    monitor.handleMouseUp(at: location, clickCount: 1, modifierFlags: [])
    #expect(selections.isEmpty)

    await monitor.handleModifierFlagsChanged(
      flags(for: modifier), at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(selections == ["selected range"])
    #expect(locations == [location])
  }

  @Test("activation ignores other modifiers and rereads selection on the next press")
  func activationOnlyTriggersOnConfiguredKeyPress() async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.selectedText = "first selection"
    accessibility.focusedTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)
    monitor.requireActivationModifier = true
    monitor.start()
    defer { monitor.stop() }

    var selections: [String] = []
    var dismissals = 0
    monitor.onTextSelected = { text, _ in selections.append(text) }
    monitor.onDismissRequested = { dismissals += 1 }
    let location = NSPoint(x: 40, y: 80)
    await monitor.handleModifierFlagsChanged(
      .shift, at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(selections.isEmpty)

    await monitor.handleModifierFlagsChanged(
      .option, at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    await monitor.handleModifierFlagsChanged(
      [.option, .shift], at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    await monitor.handleModifierFlagsChanged(
      [], at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(selections == ["first selection"])
    #expect(dismissals == 0)

    accessibility.selectedText = "second selection"
    await monitor.handleModifierFlagsChanged(
      .option, at: location, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(selections == ["first selection", "second selection"])
  }

  @Test("modifier presses do not query selections when Do Not Disturb is disabled")
  func activationIsDisabledOutsideDoNotDisturb() async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.selectedText = "selected range"
    accessibility.focusedTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)
    monitor.start()
    defer { monitor.stop() }

    await monitor.handleModifierFlagsChanged(
      .option, at: .zero, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(accessibility.selectedTextQueryCount == 0)
  }

  @Test("activation key respects ignored apps and SelectionBar-owned UI", arguments: [false, true])
  func activationSkipsExcludedContexts(ownedBySelectionBar: Bool) async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.selectedText = "selected range"
    accessibility.focusedTextContext = true
    accessibility.focusedElementOwnedByCurrentProcess = ownedBySelectionBar
    let monitor = makeMonitor(accessibility: accessibility)
    monitor.requireActivationModifier = true
    if !ownedBySelectionBar {
      monitor.ignoredBundleIDs = ["com.example.Editor"]
    }
    monitor.start()
    defer { monitor.stop() }

    await monitor.handleModifierFlagsChanged(
      .option, at: .zero, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(accessibility.selectedTextQueryCount == 0)
  }

  @Test("activation key does not show a toolbar without selected text")
  func activationRequiresSelectedText() async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)
    monitor.requireActivationModifier = true
    monitor.start()
    defer { monitor.stop() }

    var selections: [String] = []
    monitor.onTextSelected = { text, _ in selections.append(text) }
    await monitor.handleModifierFlagsChanged(
      .option, at: .zero, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(accessibility.selectedTextQueryCount == 1)
    #expect(selections.isEmpty)
  }

  @Test("activation key can read a selection through clipboard fallback")
  func activationSupportsClipboardFallback() async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextContext = true
    let clipboard = FakeSelectionMonitorClipboardFallback()
    clipboard.selectedText = "clipboard selection"
    let monitor = makeMonitor(accessibility: accessibility, clipboardFallback: clipboard)
    monitor.requireActivationModifier = true
    monitor.start()
    defer { monitor.stop() }

    var selections: [String] = []
    monitor.onTextSelected = { text, _ in selections.append(text) }
    await monitor.handleModifierFlagsChanged(
      .option, at: .zero, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(clipboard.copyCount == 1)
    #expect(selections == ["clipboard selection"])
  }

  @Test("stopping the monitor during clipboard fallback prevents a late popup")
  func stoppingDuringActivationPreventsLatePopup() async {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextContext = true
    let clipboard = FakeSelectionMonitorClipboardFallback()
    clipboard.selectedText = "clipboard selection"
    let monitor = makeMonitor(accessibility: accessibility, clipboardFallback: clipboard)
    monitor.requireActivationModifier = true
    monitor.start()
    defer { monitor.stop() }

    var selections: [String] = []
    monitor.onTextSelected = { text, _ in selections.append(text) }
    clipboard.onCopy = { monitor.stop() }
    await monitor.handleModifierFlagsChanged(
      .option, at: .zero, frontmostBundleID: "com.example.Editor", frontmostPID: 42
    )
    #expect(clipboard.copyCount == 1)
    #expect(selections.isEmpty)
  }

  @Test("mouse drag skips clipboard fallback without text selection signals")
  func mouseDragSkipsClipboardFallbackWithoutTextSelectionSignals() {
    let monitor = makeMonitor()

    #expect(
      !monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 40, y: 80),
        isSelectionGesture: true,
        isMultiClickGesture: false,
        didMoveWindow: false,
        allowFocusedTextContextFallback: false
      )
    )
  }

  @Test("file browser icon drag skips clipboard fallback even when AX exposes selected text")
  func fileBrowserIconDragSkipsClipboardFallbackEvenWithAXSelectedText() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextSelection = true
    let monitor = makeMonitor(accessibility: accessibility)

    #expect(
      !monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 40, y: 80),
        isSelectionGesture: true,
        isMultiClickGesture: false,
        didMoveWindow: false,
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "com.apple.finder",
        frontmostPID: 42
      )
    )
  }

  @Test("file browser icon drag skips direct AX selected text")
  func fileBrowserIconDragSkipsDirectAXSelectedText() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.hitTestTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)

    #expect(
      !monitor.shouldAcceptAccessibilitySelectedText(
        at: NSPoint(x: 40, y: 80),
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "com.apple.finder"
      )
    )
  }

  @Test("file browser editable text keeps direct AX selected text")
  func fileBrowserEditableTextKeepsDirectAXSelectedText() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedElementEditable = true
    let monitor = makeMonitor(accessibility: accessibility)

    #expect(
      monitor.shouldAcceptAccessibilitySelectedText(
        at: NSPoint(x: 40, y: 80),
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "com.apple.finder"
      )
    )
  }

  @Test("Xcode project navigator double click is treated as open action")
  func xcodeProjectNavigatorDoubleClickIsOpenAction() {
    let monitor = makeMonitor()

    #expect(
      monitor.shouldIgnoreMultiClickOpenAction(
        frontmostBundleID: "com.apple.dt.Xcode",
        clickCount: 2,
        isEditableTextTarget: false
      )
    )
  }

  @Test("Xcode editable text double click is allowed")
  func xcodeEditableTextDoubleClickIsAllowed() {
    let monitor = makeMonitor()

    #expect(
      !monitor.shouldIgnoreMultiClickOpenAction(
        frontmostBundleID: "com.apple.dt.Xcode",
        clickCount: 2,
        isEditableTextTarget: true
      )
    )
  }

  @Test("direct AX selected text requires text context outside file browsers")
  func directAXSelectedTextRequiresTextContextOutsideFileBrowsers() {
    let monitor = makeMonitor()

    #expect(
      !monitor.shouldAcceptAccessibilitySelectedText(
        at: NSPoint(x: 40, y: 80),
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "com.example.Canvas"
      )
    )
  }

  @Test("direct AX selected text allows text hit-test context")
  func directAXSelectedTextAllowsTextHitTestContext() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.hitTestTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)

    #expect(
      monitor.shouldAcceptAccessibilitySelectedText(
        at: NSPoint(x: 40, y: 80),
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "com.example.Editor"
      )
    )
  }

  @Test("mouse drag preserves existing window-move safeguard")
  func mouseDragSkipsClipboardFallbackWhenWindowMoves() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextSelection = true
    let monitor = makeMonitor(
      accessibility: accessibility,
      clipboardFallbackIncludedBundleIDs: ["com.tencent.xinWeChat"]
    )

    #expect(
      !monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 40, y: 80),
        isSelectionGesture: true,
        isMultiClickGesture: false,
        didMoveWindow: true,
        allowFocusedTextContextFallback: false
      )
    )
  }

  @Test("mouse drag allows clipboard fallback when AX reports active text selection")
  func mouseDragAllowsClipboardFallbackWithActiveSelection() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextSelection = true
    let monitor = makeMonitor(
      accessibility: accessibility,
      clipboardFallbackIncludedBundleIDs: ["ru.keepcoder.Telegram"]
    )

    #expect(
      monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 40, y: 80),
        isSelectionGesture: true,
        isMultiClickGesture: false,
        didMoveWindow: false,
        allowFocusedTextContextFallback: false
      )
    )
  }

  @Test("double click allows clipboard fallback in strict text hit-test context")
  func doubleClickAllowsClipboardFallbackInTextContext() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.hitTestTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)

    #expect(
      monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 20, y: 30),
        isSelectionGesture: true,
        isMultiClickGesture: true,
        didMoveWindow: false,
        allowFocusedTextContextFallback: false
      )
    )
  }

  @Test("keyboard selection can fall back from focused text context")
  func keyboardSelectionAllowsFocusedTextContextFallback() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.focusedTextContext = true
    let monitor = makeMonitor(accessibility: accessibility)

    #expect(
      monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 0, y: 0),
        isSelectionGesture: true,
        isMultiClickGesture: true,
        didMoveWindow: false,
        allowFocusedTextContextFallback: true
      )
    )
  }

  @Test("window-only AX apps can still use clipboard fallback outside chrome")
  func windowOnlyAXAppsAllowClipboardFallbackOutsideChrome() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.pointLikelyInFocusedWindowChrome = false
    let monitor = makeMonitor(
      accessibility: accessibility,
      clipboardFallbackIncludedBundleIDs: ["com.tencent.xinWeChat"]
    )

    #expect(
      monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 12, y: 24),
        isSelectionGesture: true,
        isMultiClickGesture: false,
        didMoveWindow: false,
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "com.tencent.xinWeChat",
        frontmostPID: 42
      )
    )
  }

  @Test("window-only AX apps still skip clipboard fallback in chrome")
  func windowOnlyAXAppsSkipClipboardFallbackInChrome() {
    let accessibility = FakeSelectionMonitorAccessibility()
    accessibility.pointLikelyInFocusedWindowChrome = true
    let monitor = makeMonitor(
      accessibility: accessibility,
      clipboardFallbackIncludedBundleIDs: ["ru.keepcoder.Telegram"]
    )

    #expect(
      !monitor.shouldAttemptClipboardFallback(
        at: NSPoint(x: 12, y: 24),
        isSelectionGesture: true,
        isMultiClickGesture: false,
        didMoveWindow: false,
        allowFocusedTextContextFallback: false,
        frontmostBundleID: "ru.keepcoder.Telegram",
        frontmostPID: 42
      )
    )
  }

  private func makeMonitor(
    accessibility: FakeSelectionMonitorAccessibility = FakeSelectionMonitorAccessibility(),
    clipboardFallback: FakeSelectionMonitorClipboardFallback =
      FakeSelectionMonitorClipboardFallback(),
    clipboardFallbackIncludedBundleIDs: Set<String> = []
  ) -> SelectionMonitor {
    let monitor = SelectionMonitor(
      accessibility: accessibility,
      clipboardFallback: clipboardFallback
    )
    monitor.clipboardFallbackIncludedBundleIDs = clipboardFallbackIncludedBundleIDs
    return monitor
  }

  private func flags(for modifier: SelectionBarActivationModifier) -> NSEvent.ModifierFlags {
    switch modifier {
    case .command: .command
    case .option: .option
    case .control: .control
    case .shift: .shift
    }
  }
}

@MainActor
private final class FakeSelectionMonitorAccessibility: SelectionMonitorAccessibilityProviding {
  var focusedElementEditable = false
  var focusedTextSelection = false
  var hitTestTextSelection = false
  var hitTestTextContext = false
  var focusedTextContext = false
  var pointLikelyInFocusedWindowChrome = false
  var selectedText: String?
  var selectedTextQueryCount = 0
  var focusedElementOwnedByCurrentProcess = false

  @discardableResult
  func checkAccessibilityPermission(promptIfNeeded _: Bool) -> Bool {
    true
  }

  func isFocusedElementEditable() -> Bool {
    focusedElementEditable
  }

  func isEditableTextContext(at _: NSPoint) -> Bool {
    focusedElementEditable
  }

  func selectedTextFromFocusedHierarchy() -> String? {
    selectedTextQueryCount += 1
    return selectedText
  }

  func hasFocusedTextSelection() -> Bool {
    focusedTextSelection
  }

  func hasTextSelection(at _: NSPoint) -> Bool {
    hitTestTextSelection
  }

  func isPointLikelyInFocusedWindowChrome(at _: NSPoint, forPID _: pid_t) -> Bool {
    pointLikelyInFocusedWindowChrome
  }

  func isTextContext(at _: NSPoint) -> Bool {
    hitTestTextContext
  }

  func isCurrentProcessElement(at _: NSPoint) -> Bool {
    false
  }

  func isFocusedElementOwnedByCurrentProcess() -> Bool {
    focusedElementOwnedByCurrentProcess
  }

  func isFocusedTextContext() -> Bool {
    focusedTextContext
  }

  func focusedWindowOrigin(forPID _: pid_t) -> CGPoint? {
    nil
  }
}

@MainActor
private final class FakeSelectionMonitorClipboardFallback:
  SelectionMonitorClipboardFallbackProviding
{
  var selectedText: String?
  var copyCount = 0
  var onCopy: (() -> Void)?

  func selectedTextByCopyCommand() async -> String? {
    copyCount += 1
    onCopy?()
    return selectedText
  }
}
