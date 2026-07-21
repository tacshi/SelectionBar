import AppKit
import Foundation

/// A copy of a pasteboard's full contents, so it can be put back after the app
/// temporarily borrows the clipboard to synthesize a copy or paste.
///
/// The pasteboard holds an *array* of items — copying three files in Finder
/// produces three items, each with its own type/data pairs. Capturing only
/// `pasteboard.types` would silently collapse that to the first item and lose
/// the rest on restore, so every item is captured individually.
struct PasteboardSnapshot {
  private let items: [[NSPasteboard.PasteboardType: Data]]

  var isEmpty: Bool { items.allSatisfy(\.isEmpty) }

  init(capturing pasteboard: NSPasteboard) {
    items = (pasteboard.pasteboardItems ?? []).map { item in
      var contents: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) {
          contents[type] = data
        }
      }
      return contents
    }
  }

  /// Puts the snapshot back. Returns the pasteboard's new change count, or nil
  /// if there was nothing to restore.
  @discardableResult
  func restore(to pasteboard: NSPasteboard) -> Int? {
    guard !isEmpty else { return nil }
    let changeCount = pasteboard.clearContents()
    // Rebuild fresh items: an NSPasteboardItem that has already been written to
    // a pasteboard cannot be written again.
    let restored = items.compactMap { contents -> NSPasteboardItem? in
      guard !contents.isEmpty else { return nil }
      let item = NSPasteboardItem()
      for (type, data) in contents {
        item.setData(data, forType: type)
      }
      return item
    }
    pasteboard.writeObjects(restored)
    return changeCount
  }
}
