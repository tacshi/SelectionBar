import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "SelectionBarClipboardService")

@MainActor
final class SelectionBarClipboardService {
  func replaceSelectedText(with text: String) async {
    let pasteboard = NSPasteboard.general

    let savedItems = savePasteboardContents(pasteboard)
    let savedChangeCount = pasteboard.changeCount

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    try? await Task.sleep(for: .milliseconds(50))

    simulatePaste()

    try? await Task.sleep(for: .milliseconds(200))

    if pasteboard.changeCount == savedChangeCount + 1 {
      restorePasteboardContents(pasteboard, items: savedItems)
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

  /// Save all pasteboard items (types + data).
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

  /// Restore saved pasteboard items.
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
