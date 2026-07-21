import Foundation

enum SFSymbolCatalog {
  static let names: [String] = {
    let paths = [
      "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist",
      "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist",
    ]

    for path in paths {
      guard let symbols = NSArray(contentsOfFile: path) as? [String], !symbols.isEmpty else {
        continue
      }
      return symbols
    }

    return [
      "sparkles",
      "wand.and.stars",
      "text.badge.checkmark",
      "eraser",
      "checklist",
      "list.bullet",
      "text.alignleft",
      "doc.text",
      "quote.bubble",
      "envelope",
      "lightbulb",
      "magnifyingglass",
      "bolt",
      "gearshape",
      "paperplane",
      "bookmark",
      "pencil",
    ]
  }()
}
