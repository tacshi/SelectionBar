import Foundation

enum GrammarSuggestionCategory: String, Codable, Sendable {
  case correctness, clarity, tone
}

enum GrammarCheckResult: Equatable, Sendable {
  case suggestions([GrammarSuggestion])
  case rewrite(String)
}

enum GrammarSourceStatus { case current, changed, differentContext }

enum GrammarReviewPhase: Equatable {
  case checking, ready, stale, applying, completed, failed
}

struct GrammarSuggestion: Identifiable, Equatable, Sendable {
  let id: UUID
  let original: String
  let replacement: String
  let category: GrammarSuggestionCategory
  let explanation: String
  var range: NSRange
}

struct GrammarTextSnapshot: Equatable {
  let targetID: UUID
  let processID: Int32
  let bundleID: String
  var fullText: String?
  var checkedRange: NSRange
  var selectionRange: NSRange?
  var text: String
  var anchor: CGPoint
  var canApply: Bool
  var selectedTextAtCapture: String? = nil

  func hasSameContent(as other: Self) -> Bool {
    targetID == other.targetID && processID == other.processID
      && GrammarText.identical(fullText, other.fullText) && checkedRange == other.checkedRange
      && GrammarText.identical(text, other.text)
  }
}

enum GrammarCheckError: LocalizedError, Equatable {
  case unavailable, empty, tooLong, composition, changed, invalidResult, applyFailed,
    providerMissing

  var errorDescription: String? {
    switch self {
    case .unavailable:
      String(localized: "Select text in an editor, then check again.", bundle: .localizedModule)
    case .empty:
      String(localized: "Select text or place the caret in a paragraph.", bundle: .localizedModule)
    case .tooLong:
      String(
        localized: "Select a shorter passage (up to 8,000 characters).", bundle: .localizedModule)
    case .composition:
      String(localized: "Finish composing text, then check again.", bundle: .localizedModule)
    case .changed:
      String(localized: "The text or focused field changed. Check again.", bundle: .localizedModule)
    case .invalidResult:
      String(
        localized: "The model returned invalid suggestions. Try again or choose another model.",
        bundle: .localizedModule)
    case .applyFailed:
      String(
        localized: "Could not verify the edit. Check the text before trying again.",
        bundle: .localizedModule)
    case .providerMissing:
      String(
        localized: "Choose an available provider in Grammar settings.", bundle: .localizedModule)
    }
  }
}

enum GrammarText {
  static let maximumCharacters = 8_000

  /// AX ranges use UTF-16 positions. Canonically equivalent strings can have different positions.
  static func identical(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return lhs.utf16.elementsEqual(rhs.utf16)
  }

  static func checkedRange(in text: String, selection: NSRange, preferSelection: Bool) throws
    -> NSRange
  {
    guard Range(selection, in: text) != nil else { throw GrammarCheckError.unavailable }
    if preferSelection && selection.length > 0 { return selection }
    // Paragraph boundaries come from the editor's text, not visual line wrapping.
    let string = text as NSString
    var range = string.paragraphRange(for: NSRange(location: selection.location, length: 0))
    // A caret on a blank line (e.g. just after Return) refers to the paragraph above it.
    var previous = range
    while string.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      previous.location > 0
    {
      previous = string.paragraphRange(for: NSRange(location: previous.location - 1, length: 0))
    }
    if !string.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      range = previous
    }
    return range
  }

  static func validate(_ text: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw GrammarCheckError.empty
    }
    guard text.count <= maximumCharacters else { throw GrammarCheckError.tooLong }
  }

  static func replacing(_ text: String, with suggestions: [GrammarSuggestion]) -> String {
    suggestions.sorted { $0.range.location > $1.range.location }.reduce(text) {
      result, suggestion in
      (result as NSString).replacingCharacters(in: suggestion.range, with: suggestion.replacement)
    }
  }
}
