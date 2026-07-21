import AppKit
import Carbon.HIToolbox
import Foundation
import os.log

private let logger = Logger(
  subsystem: "com.selectionbar",
  category: "SelectionMonitorClipboardFallback"
)

@MainActor
final class SelectionMonitorClipboardFallback: SelectionMonitorClipboardFallbackProviding {
  func selectedTextByCopyCommand() async -> String? {
    let pasteboard = NSPasteboard.general

    let savedChangeCount = pasteboard.changeCount
    let snapshot = PasteboardSnapshot(capturing: pasteboard)

    let secureInput = IsSecureEventInputEnabled()
    simulateCopy(secureInput: secureInput)

    var clipboardChanged = false
    for poll in 1...5 {
      try? await Task.sleep(for: .milliseconds(100))
      if pasteboard.changeCount != savedChangeCount {
        clipboardChanged = true
        logger.debug("Clipboard changed on poll iteration \(poll)")
        break
      }
    }

    guard clipboardChanged else {
      if secureInput {
        logger.debug("Clipboard fallback failed: SecureEventInput is active (password field?)")
      } else {
        logger.debug("Clipboard fallback failed: pasteboard did not change after Cmd+C")
      }
      // The target app may still service the synthesized Cmd+C after we stop
      // waiting. Without this, a late copy silently replaces the user's
      // clipboard for good.
      scheduleLateRestore(pasteboard, snapshot: snapshot, expecting: savedChangeCount)
      return nil
    }

    let copiedText = pasteboard.string(forType: .string)
    snapshot.restore(to: pasteboard)

    guard let copiedText else { return nil }
    let trimmed = copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed
  }

  /// How long to keep watching for a synthesized copy that arrived after the
  /// poll loop gave up. Kept short: everything in this window is attributed to
  /// our own Cmd+C, so a genuine user copy landing here would be undone.
  private static let lateRestoreWindow = Duration.milliseconds(600)
  private static let lateRestorePollInterval = Duration.milliseconds(100)

  /// Keeps watching the pasteboard after the poll loop gave up, and puts the
  /// user's clipboard back if the synthesized copy arrives late.
  ///
  /// Only a *single* change is treated as ours. If the change count has moved
  /// by more than one, something else — the user, or a clipboard manager — has
  /// also written, and the clipboard is left alone rather than reverted.
  private func scheduleLateRestore(
    _ pasteboard: NSPasteboard,
    snapshot: PasteboardSnapshot,
    expecting savedChangeCount: Int
  ) {
    guard !snapshot.isEmpty else { return }
    let polls = Int(
      Self.lateRestoreWindow / Self.lateRestorePollInterval
    )
    Task { @MainActor in
      for _ in 1...max(1, polls) {
        try? await Task.sleep(for: Self.lateRestorePollInterval)
        let changeCount = pasteboard.changeCount
        guard changeCount != savedChangeCount else { continue }
        guard changeCount == savedChangeCount + 1 else {
          logger.debug("Clipboard changed more than once — leaving it alone")
          return
        }
        logger.debug("Late clipboard change detected — restoring saved contents")
        snapshot.restore(to: pasteboard)
        return
      }
    }
  }

  private func simulateCopy(secureInput: Bool) {
    if secureInput {
      logger.warning("SecureEventInput is active — synthesized Cmd+C may be silently swallowed")
    }

    // Use .privateState to avoid inheriting hardware modifier state (e.g. Shift
    // held during drag-select) and to prevent corrupting the system's global
    // modifier tracking.
    let source = CGEventSource(stateID: .privateState)

    // Full modifier key sequence matching real hardware:
    //   Command↓ → C↓ → C↑ → Command↑
    // Apps with custom event handling (e.g. WeChat) may require the complete
    // sequence rather than just C key events with Command flags.

    // Key code 55 = Left Command, 8 = 'C'
    guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true) else {
      logger.error("Failed to create Command key-down event")
      return
    }
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) else {
      logger.error("Failed to create C key-down event")
      return
    }
    guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
      logger.error("Failed to create C key-up event")
      return
    }
    guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
      logger.error("Failed to create Command key-up event")
      return
    }

    cmdDown.flags = .maskCommand
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    cmdUp.flags = []

    // Post at session level — HID-level events are invisible to some apps.
    cmdDown.post(tap: .cgSessionEventTap)
    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
    cmdUp.post(tap: .cgSessionEventTap)
  }

}
