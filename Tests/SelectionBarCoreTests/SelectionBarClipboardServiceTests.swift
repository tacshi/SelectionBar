import AppKit
import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarClipboardService Tests")
@MainActor
struct SelectionBarClipboardServiceTests {
  @Test("copied text removes controls and default-ignorable carriers")
  func copiedTextRemovesInvisibleCarriers() {
    let input =
      "a\u{200B}b\u{202E}c\u{E0061}d\u{FEFF}e\u{00AD}f\u{2060}g\u{0000}h"

    #expect(CopiedTextSanitizer.sanitize(input) == "abcdefgh")
  }

  @Test("copied text preserves whitespace, shaping, and variation scalars")
  func copiedTextPreservesMeaningfulInvisibleScalars() {
    let input =
      "first\tline\r\nCafe\u{0301} | می\u{200C}خواهم | 👩\u{200D}💻 | ❤️ | ᠠ\u{180B} | 一\u{E0100}"

    #expect(CopiedTextSanitizer.sanitize(input) == input)
  }

  @Test("copy writes sanitized text to the requested pasteboard")
  func copyWritesSanitizedText() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    SelectionBarClipboardService().copyToClipboard(
      "clean\u{200B} text\u{FEFF}",
      pasteboard: pasteboard
    )

    #expect(pasteboard.string(forType: .string) == "clean text")
  }

  @Test("copy replaces stale clipboard contents when sanitization produces an empty string")
  func copyWritesEmptySanitizedText() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("stale", forType: .string)

    SelectionBarClipboardService().copyToClipboard(
      "\u{200B}\u{FEFF}\u{0000}",
      pasteboard: pasteboard
    )

    #expect(pasteboard.string(forType: .string) == "")
  }

  private func makeScratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("SelectionBarClipboardTests.\(UUID().uuidString)"))
  }
}
