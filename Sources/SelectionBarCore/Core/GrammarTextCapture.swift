import Foundation

/// Text attributes from one node in the focused element's Accessibility hierarchy.
struct GrammarAccessibleText {
  var fullText: String? = nil
  var selectedRange: NSRange? = nil
  var selectedText: String? = nil
  var isEditable = false
  var canSelectRange = false
}

struct GrammarCapturedText {
  let sourceIndex: Int
  let fullText: String?
  let checkedRange: NSRange
  let selectionRange: NSRange?
  let text: String
  let canApply: Bool
}

enum GrammarTextCapture {
  static func resolve(
    _ sources: [GrammarAccessibleText], preferSelection: Bool
  ) throws -> GrammarCapturedText {
    var sawEmptyText = false
    if preferSelection {
      // Virtual editors can expose a blank input proxy while selected text lives on another node.
      // Inspect explicit selections throughout the hierarchy before considering any paragraph.
      for (index, source) in sources.enumerated() {
        guard let text = source.selectedText, !text.isEmpty else { continue }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          sawEmptyText = true
          continue
        }
        try GrammarText.validate(text)
        if let value = source.fullText, let range = source.selectedRange,
          Range(range, in: value) != nil,
          GrammarText.identical((value as NSString).substring(with: range), text)
        {
          return boundedCapture(source, index: index, range: range, text: text)
        }
        // A usable selection is enough to check, but not enough to safely edit an unknown range.
        return GrammarCapturedText(
          sourceIndex: index, fullText: nil,
          checkedRange: NSRange(location: 0, length: text.utf16.count), selectionRange: nil,
          text: text, canApply: false)
      }

      var hasSelectionRange = false
      for (index, source) in sources.enumerated() {
        guard let range = source.selectedRange, range.length > 0 else { continue }
        hasSelectionRange = true
        guard let value = source.fullText, Range(range, in: value) != nil else { continue }
        let text = (value as NSString).substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          sawEmptyText = true
          continue
        }
        try GrammarText.validate(text)
        return boundedCapture(source, index: index, range: range, text: text)
      }
      // An unreadable selection must not silently turn into a check of an unrelated paragraph.
      if hasSelectionRange { throw sawEmptyText ? GrammarCheckError.empty : .unavailable }
    }

    for (index, source) in sources.enumerated() {
      guard source.isEditable, let value = source.fullText, let selection = source.selectedRange,
        let range = try? GrammarText.checkedRange(
          in: value, selection: selection, preferSelection: false)
      else { continue }
      let text = (value as NSString).substring(with: range)
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        sawEmptyText = true
        continue
      }
      try GrammarText.validate(text)
      return boundedCapture(source, index: index, range: range, text: text)
    }
    throw sawEmptyText ? GrammarCheckError.empty : .unavailable
  }

  private static func boundedCapture(
    _ source: GrammarAccessibleText, index: Int, range: NSRange, text: String
  ) -> GrammarCapturedText {
    GrammarCapturedText(
      sourceIndex: index, fullText: source.fullText, checkedRange: range,
      selectionRange: source.selectedRange, text: text,
      canApply: source.isEditable && source.canSelectRange)
  }
}
