import Foundation
import Testing

@testable import SelectionBarCore

@Suite("Grammar text capture")
struct GrammarTextCaptureTests {
  private let selected = "Required address text of up to 200 characters"

  @Test("A selected comment survives an empty editor proxy value")
  func selectionWithEmptyValue() throws {
    let source = GrammarAccessibleText(
      fullText: "", selectedRange: NSRange(location: 0, length: 0),
      selectedText: selected, isEditable: true, canSelectRange: true)
    let result = try GrammarTextCapture.resolve([source], preferSelection: true)
    #expect(result.text == selected)
    #expect(!result.canApply)
    #expect(result.fullText == nil)
  }

  @Test(
    "An empty or invalid proxy cannot hide a valid selection in its parent", arguments: [0, 100])
  func selectionInParent(proxyOffset: Int) throws {
    let proxy = GrammarAccessibleText(
      fullText: "", selectedRange: NSRange(location: proxyOffset, length: 0), isEditable: true)
    let fullText = "// " + selected + ".\noptional string query = 1;"
    let range = (fullText as NSString).range(of: selected)
    let editor = GrammarAccessibleText(
      fullText: fullText, selectedRange: range, isEditable: true, canSelectRange: true)
    let result = try GrammarTextCapture.resolve([proxy, editor], preferSelection: true)
    #expect(result.sourceIndex == 1)
    #expect(result.text == selected)
    #expect(result.checkedRange == range)
    #expect(result.canApply)
  }

  @Test("Explicit selection wins over a nonempty proxy paragraph")
  func selectionBeforeParagraph() throws {
    let proxy = GrammarAccessibleText(
      fullText: "unrelated proxy text", selectedRange: NSRange(location: 0, length: 0),
      isEditable: true)
    let editor = GrammarAccessibleText(selectedText: selected)
    #expect(
      try GrammarTextCapture.resolve([proxy, editor], preferSelection: true).text == selected)
  }

  @Test("A whitespace selection attribute cannot mask a real selection")
  func whitespaceProxy() throws {
    let result = try GrammarTextCapture.resolve(
      [
        GrammarAccessibleText(selectedText: " \n"), GrammarAccessibleText(selectedText: selected),
      ], preferSelection: true)
    #expect(result.text == selected)
  }

  @Test("Conflicting selection attributes produce copyable text without an unsafe Apply")
  func inconsistentSelectionRange() throws {
    let source = GrammarAccessibleText(
      fullText: "different text", selectedRange: NSRange(location: 0, length: 9),
      selectedText: selected, isEditable: true, canSelectRange: true)
    let result = try GrammarTextCapture.resolve([source], preferSelection: true)
    #expect(result.text == selected)
    #expect(!result.canApply)
    #expect(result.fullText == nil)
  }

  @Test("A matching Unicode selection retains its exact native range")
  func verifiedSelection() throws {
    let text = "👩‍💻 // Cafe\u{301} 我们 write 日本語.\n"
    let selection = "Cafe\u{301} 我们 write 日本語"
    let range = (text as NSString).range(of: selection)
    let source = GrammarAccessibleText(
      fullText: text, selectedRange: range, selectedText: selection,
      isEditable: true, canSelectRange: true)
    let result = try GrammarTextCapture.resolve([source], preferSelection: true)
    #expect(result.text == selection)
    #expect(result.checkedRange == range)
    #expect(result.canApply)
  }

  @Test("Read-only and canonically equivalent but mismatched selections cannot be applied")
  func unsafeRanges() throws {
    let readOnly = GrammarAccessibleText(
      fullText: selected, selectedRange: NSRange(location: 0, length: selected.utf16.count),
      selectedText: selected, canSelectRange: true)
    #expect(try !GrammarTextCapture.resolve([readOnly], preferSelection: true).canApply)
    let normalized = GrammarAccessibleText(
      fullText: "Cafe\u{301}", selectedRange: NSRange(location: 0, length: 5),
      selectedText: "Café", isEditable: true, canSelectRange: true)
    let result = try GrammarTextCapture.resolve([normalized], preferSelection: true)
    #expect(!result.canApply)
    #expect(result.fullText == nil)
  }

  @Test("Whitespace and unreadable selections never switch to an unrelated paragraph")
  func unavailableSelection() {
    let paragraph = GrammarAccessibleText(
      fullText: "Another paragraph", selectedRange: NSRange(location: 0, length: 0),
      isEditable: true)
    let whitespace = GrammarAccessibleText(
      fullText: " \ntext", selectedRange: NSRange(location: 0, length: 2), isEditable: true)
    #expect(throws: GrammarCheckError.empty) {
      try GrammarTextCapture.resolve([whitespace, paragraph], preferSelection: true)
    }
    let invalid = GrammarAccessibleText(
      fullText: "", selectedRange: NSRange(location: 100, length: 5), isEditable: true)
    #expect(throws: GrammarCheckError.unavailable) {
      try GrammarTextCapture.resolve([invalid, paragraph], preferSelection: true)
    }
  }

  @Test("Oversized selections do not fall back to a different short paragraph")
  func oversizedSelection() throws {
    let source = GrammarAccessibleText(
      fullText: "short paragraph", selectedRange: NSRange(location: 0, length: 0),
      selectedText: String(repeating: "a", count: 8_001), isEditable: true)
    #expect(throws: GrammarCheckError.tooLong) {
      try GrammarTextCapture.resolve([source], preferSelection: true)
    }
  }

  @Test("Automatic checks still use the caret paragraph and skip empty proxies")
  func automaticParagraph() throws {
    let proxy = GrammarAccessibleText(
      fullText: "", selectedRange: NSRange(location: 0, length: 0), isEditable: true)
    let editor = GrammarAccessibleText(
      fullText: "First paragraph.\nSecond paragraph.",
      selectedRange: NSRange(location: 20, length: 0), selectedText: "unrelated selection",
      isEditable: true)
    #expect(
      try GrammarTextCapture.resolve([proxy, editor], preferSelection: false).text
        == "Second paragraph.")
  }

  @Test("A caret on a blank line checks the paragraph above it", arguments: [17, 18, 19])
  func blankLineParagraph(caret: Int) throws {
    let text = "First paragraph.\n\n\n"
    let editor = GrammarAccessibleText(
      fullText: text, selectedRange: NSRange(location: caret, length: 0), isEditable: true)
    let result = try GrammarTextCapture.resolve([editor], preferSelection: true)
    #expect(result.text == "First paragraph.\n")
    #expect(result.checkedRange == NSRange(location: 0, length: 17))
  }

  @Test("A caret inside a paragraph never widens to its neighbours")
  func paragraphOnly() throws {
    let text = "One.\n\nTwo is here.\nThree."
    let editor = GrammarAccessibleText(
      fullText: text, selectedRange: NSRange(location: 9, length: 0), isEditable: true)
    #expect(
      try GrammarTextCapture.resolve([editor], preferSelection: true).text == "Two is here.\n")
  }

  @Test("Genuinely empty fields and missing Accessibility data retain distinct errors")
  func noText() {
    let empty = GrammarAccessibleText(
      fullText: " \n", selectedRange: NSRange(location: 0, length: 0), isEditable: true)
    #expect(throws: GrammarCheckError.empty) {
      try GrammarTextCapture.resolve([empty], preferSelection: true)
    }
    #expect(throws: GrammarCheckError.unavailable) {
      try GrammarTextCapture.resolve([GrammarAccessibleText()], preferSelection: true)
    }
  }
}
