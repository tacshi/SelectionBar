import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "SelectionBarClipboardService")

@MainActor
final class SelectionBarClipboardService {
  /// How long to leave our text on the pasteboard after posting Cmd+V. Apps
  /// with heavier event loops (Electron, JetBrains) can take well over 200ms to
  /// actually read it; restoring too early makes them paste the *old* clipboard.
  private static let pasteSettleDelay = Duration.milliseconds(500)

  func replaceSelectedText(with text: String) async {
    let pasteboard = NSPasteboard.general

    let snapshot = PasteboardSnapshot(capturing: pasteboard)

    let ownedChangeCount = pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    try? await Task.sleep(for: .milliseconds(50))

    simulatePaste()

    try? await Task.sleep(for: Self.pasteSettleDelay)

    // Only put the old clipboard back if what we wrote is still there. A
    // clipboard manager bumping the change count no longer blocks the restore —
    // we compare against the text itself, so our output does not leak into the
    // user's clipboard history any longer than necessary.
    let stillOurs =
      pasteboard.changeCount == ownedChangeCount
      || pasteboard.string(forType: .string) == text
    if stillOurs {
      snapshot.restore(to: pasteboard)
    }
  }

  func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  @discardableResult
  func cutSelection() -> Bool {
    simulateCut()
  }

  @discardableResult
  func triggerKeyboardShortcut(_ shortcut: SelectionBarKeyboardShortcut) -> Bool {
    simulateKeyboardShortcut(
      keyCode: shortcut.keyCode,
      flags: shortcut.eventFlags,
      actionName: shortcut.canonicalString
    )
  }

  private func simulatePaste() {
    _ = simulateKeyboardShortcut(
      keyCode: 9,
      flags: .maskCommand,
      actionName: "paste"
    )
  }

  private func simulateCut() -> Bool {
    simulateKeyboardShortcut(
      keyCode: 7,
      flags: .maskCommand,
      actionName: "cut"
    )
  }

  @discardableResult
  private func simulateKeyboardShortcut(
    keyCode: CGKeyCode,
    flags: CGEventFlags,
    actionName: String
  ) -> Bool {
    // Use .privateState to avoid inheriting hardware modifier state and
    // prevent corrupting the system's global modifier tracking.
    let source = CGEventSource(stateID: .privateState)

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
      logger.error("Failed to create CGEvent for \(actionName, privacy: .public)")
      return false
    }

    keyDown.flags = flags
    keyUp.flags = flags

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }

}
