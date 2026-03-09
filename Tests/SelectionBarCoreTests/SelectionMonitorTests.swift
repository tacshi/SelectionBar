import AppKit
import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionMonitor Tests")
@MainActor
struct SelectionMonitorTests {
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
    clipboardFallbackIncludedBundleIDs: Set<String> = []
  ) -> SelectionMonitor {
    let monitor = SelectionMonitor(
      accessibility: accessibility,
      clipboardFallback: FakeSelectionMonitorClipboardFallback()
    )
    monitor.clipboardFallbackIncludedBundleIDs = clipboardFallbackIncludedBundleIDs
    return monitor
  }
}

@MainActor
private final class FakeSelectionMonitorAccessibility: SelectionMonitorAccessibilityProviding {
  var focusedTextSelection = false
  var hitTestTextSelection = false
  var hitTestTextContext = false
  var focusedTextContext = false
  var pointLikelyInFocusedWindowChrome = false

  @discardableResult
  func checkAccessibilityPermission(promptIfNeeded _: Bool) -> Bool {
    true
  }

  func isFocusedElementEditable() -> Bool {
    false
  }

  func selectedTextFromFocusedHierarchy() -> String? {
    nil
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
    false
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
  func selectedTextByCopyCommand() async -> String? {
    nil
  }
}
