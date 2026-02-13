import AppKit
import Carbon.HIToolbox
import Foundation
import os.log

private let logger = Logger(
  subsystem: "com.selectionbar",
  category: "SelectionMonitorClipboardFallback"
)

@MainActor
final class SelectionMonitorClipboardFallback {
  func selectedTextByCopyCommand() async -> String? {
    let pasteboard = NSPasteboard.general

    let savedChangeCount = pasteboard.changeCount
    let savedItems = savePasteboardContents(pasteboard)

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
      return nil
    }

    let copiedText = pasteboard.string(forType: .string)
    restorePasteboardContents(pasteboard, items: savedItems)

    guard let copiedText else { return nil }
    let trimmed = copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed
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

  private func savePasteboardContents(_ pasteboard: NSPasteboard) -> [(
    NSPasteboard.PasteboardType, Data
  )] {
    var items: [(NSPasteboard.PasteboardType, Data)] = []
    guard let types = pasteboard.types else { return items }
    for type in types {
      if let data = pasteboard.data(forType: type) {
        items.append((type, data))
      }
    }
    return items
  }

  private func restorePasteboardContents(
    _ pasteboard: NSPasteboard,
    items: [(NSPasteboard.PasteboardType, Data)]
  ) {
    guard !items.isEmpty else { return }
    pasteboard.clearContents()
    for (type, data) in items {
      pasteboard.setData(data, forType: type)
    }
  }
}
