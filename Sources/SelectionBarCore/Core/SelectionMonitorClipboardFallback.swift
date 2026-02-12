import AppKit
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

    simulateCopy()

    var clipboardChanged = false
    for _ in 0..<3 {
      try? await Task.sleep(for: .milliseconds(75))
      if pasteboard.changeCount != savedChangeCount {
        clipboardChanged = true
        break
      }
    }

    guard clipboardChanged else {
      logger.debug("Clipboard fallback failed: pasteboard did not change after Cmd+C")
      return nil
    }

    let copiedText = pasteboard.string(forType: .string)
    restorePasteboardContents(pasteboard, items: savedItems)

    guard let copiedText else { return nil }
    let trimmed = copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed
  }

  private func simulateCopy() {
    // Use .privateState to avoid inheriting hardware modifier state (e.g. Shift
    // held during drag-select) and to prevent corrupting the system's global
    // modifier tracking.
    let source = CGEventSource(stateID: .privateState)

    // Key code 8 = 'C'
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
    else { return }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
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
