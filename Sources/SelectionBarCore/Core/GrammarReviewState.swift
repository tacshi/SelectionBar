import Foundation
import Observation

enum GrammarRecoveryAction { case retry, settings, clipboard }

struct GrammarReviewFailure {
  let message: String
  let recovery: GrammarRecoveryAction
}

enum GrammarReviewFocus: Hashable {
  case suggestion(UUID)
  case footer
}

@MainActor
@Observable
final class GrammarReviewState {
  var profile = GrammarWritingProfile()
  var phase: GrammarReviewPhase = .checking
  var result: GrammarCheckResult?
  var originalText = ""
  var previewOriginalText = ""
  var failure: GrammarReviewFailure?
  var sourceCanApply = false
  var hasUndo = false
  var appliedCount = 0
  var dismissedCount = 0
  var focus: GrammarReviewFocus?
  var focusRevision = 0
  /// The suggestion highlighted in the source text and scrolled into view in the review.
  var highlighted: UUID?

  /// The suggestion the footer's Accept and Dismiss act on.
  var selected: UUID?

  var currentSuggestion: GrammarSuggestion? {
    suggestions.first { $0.id == selected } ?? suggestions.first
  }

  func requestFocus(_ target: GrammarReviewFocus) {
    if case .suggestion(let id) = target { selected = id }
    focus = target
    focusRevision += 1
  }

  var suggestions: [GrammarSuggestion] {
    get {
      if case .suggestions(let suggestions) = result { return suggestions }
      return []
    }
    set { result = .suggestions(newValue) }
  }

  var canApply: Bool {
    sourceCanApply && phase == .ready && hasChanges
  }

  var canUndo: Bool { hasUndo && (phase == .ready || phase == .completed) }

  var hasChanges: Bool {
    switch result {
    case .suggestions(let suggestions): !suggestions.isEmpty
    case .rewrite(let text): !GrammarText.identical(originalText, text)
    case nil: false
    }
  }

  var outputText: String? {
    switch result {
    case .suggestions(let suggestions): GrammarText.replacing(originalText, with: suggestions)
    case .rewrite(let text): text
    case nil: nil
    }
  }

  var completionText: String {
    let applied =
      appliedCount == 1
      ? String(localized: "Applied 1 change", bundle: .localizedModule)
      : String.localizedStringWithFormat(
        String(localized: "Applied %lld changes", bundle: .localizedModule), Int64(appliedCount))
    let dismissed =
      dismissedCount == 1
      ? String(localized: "Dismissed 1 suggestion", bundle: .localizedModule)
      : String.localizedStringWithFormat(
        String(localized: "Dismissed %lld suggestions", bundle: .localizedModule),
        Int64(dismissedCount))
    if appliedCount > 0 && dismissedCount > 0 {
      return "\(applied) · \(dismissed)"
    }
    if appliedCount > 0 { return applied }
    if dismissedCount > 0 { return dismissed }
    return String(localized: "No changes suggested", bundle: .localizedModule)
  }
}
