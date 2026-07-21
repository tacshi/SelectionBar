import Foundation
import Testing

@testable import SelectionBarCore

@Suite("URLSchemeNormalizer Tests")
struct URLSchemeNormalizerTests {

  // MARK: - Empty and whitespace input

  @Test("empty and whitespace-only input is rejected")
  func emptyInput() {
    #expect(normalizedURLScheme("") == nil)
    #expect(normalizedURLScheme("   ") == nil)
    #expect(normalizedURLScheme("\n\t ") == nil)
  }

  @Test("surrounding whitespace is trimmed")
  func whitespaceIsTrimmed() {
    #expect(normalizedURLScheme("  myapp  ") == "myapp")
    #expect(normalizedURLScheme("\n\tmyapp\n") == "myapp")
    #expect(normalizedURLScheme("  https://example.com  ") == "https")
  }

  // MARK: - Bare schemes

  @Test("bare schemes pass through unchanged")
  func bareScheme() {
    #expect(normalizedURLScheme("myapp") == "myapp")
    #expect(normalizedURLScheme("https") == "https")
    #expect(normalizedURLScheme("mailto") == "mailto")
  }

  @Test("schemes are lowercased")
  func schemeIsLowercased() {
    #expect(normalizedURLScheme("MyApp") == "myapp")
    #expect(normalizedURLScheme("HTTPS://EXAMPLE.COM") == "https")
  }

  // MARK: - Separator stripping

  @Test("the :// separator and everything after it is stripped")
  func separatorIsStripped() {
    #expect(normalizedURLScheme("https://") == "https")
    #expect(normalizedURLScheme("https://example.com/search?q=1") == "https")
    #expect(normalizedURLScheme("myapp://search?query=hello") == "myapp")
  }

  @Test("only the first :// separator matters")
  func firstSeparatorWins() {
    #expect(normalizedURLScheme("myapp://host://path") == "myapp")
  }

  @Test("a single trailing colon is stripped")
  func trailingColonIsStripped() {
    #expect(normalizedURLScheme("mailto:") == "mailto")
    #expect(normalizedURLScheme("  myapp:  ") == "myapp")
  }

  @Test("a colon in the middle of a scheme is invalid")
  func embeddedColonIsInvalid() {
    #expect(normalizedURLScheme("mailto::") == nil)
    #expect(normalizedURLScheme("my:app") == nil)
  }

  // MARK: - Emptied-out input

  @Test("input that reduces to an empty scheme is rejected")
  func reducesToEmpty() {
    #expect(normalizedURLScheme("://example.com") == nil)
    #expect(normalizedURLScheme(":") == nil)
    #expect(normalizedURLScheme("://") == nil)
  }

  // MARK: - Character validation

  @Test("plus, minus and dot are permitted inside a scheme")
  func permittedPunctuation() {
    #expect(normalizedURLScheme("my-app") == "my-app")
    #expect(normalizedURLScheme("my.app") == "my.app")
    #expect(normalizedURLScheme("my+app") == "my+app")
    #expect(normalizedURLScheme("com.example.my-app+v2") == "com.example.my-app+v2")
  }

  @Test("digits are permitted inside a scheme")
  func digitsArePermitted() {
    #expect(normalizedURLScheme("h2app") == "h2app")
    #expect(normalizedURLScheme("app2") == "app2")
  }

  @Test("disallowed characters make the scheme invalid")
  func disallowedCharacters() {
    #expect(normalizedURLScheme("bad scheme") == nil)
    #expect(normalizedURLScheme("my_app") == nil)
    #expect(normalizedURLScheme("my/app") == nil)
    #expect(normalizedURLScheme("my?app") == nil)
    #expect(normalizedURLScheme("my#app") == nil)
    #expect(normalizedURLScheme("my%20app") == nil)
    #expect(normalizedURLScheme("my@app") == nil)
    #expect(normalizedURLScheme("{{query}}") == nil)
  }

  @Test("internal whitespace is not stripped and invalidates the scheme")
  func internalWhitespaceIsInvalid() {
    #expect(normalizedURLScheme("my app://x") == nil)
    #expect(normalizedURLScheme("a\tb") == nil)
  }

  // MARK: - Integration with the custom search engine

  @Test("normalized schemes drive custom search candidate generation")
  func integrationWithCustomSearchEngine() {
    let candidates = SelectionBarSearchEngine.custom.searchURLCandidates(
      for: "hi",
      customConfiguration: "  MyApp://ignored/path  "
    )
    #expect(candidates.first?.absoluteString == "myapp://search?query=hi")
    #expect(candidates.count == 5)
  }

  @Test("invalid schemes produce no custom search candidates")
  func integrationRejectsInvalidSchemes() {
    #expect(
      SelectionBarSearchEngine.custom.searchURLCandidates(
        for: "hi",
        customConfiguration: "bad scheme"
      ).isEmpty
    )
    #expect(
      SelectionBarSearchEngine.custom.searchURLCandidates(
        for: "hi",
        customConfiguration: "   "
      ).isEmpty
    )
  }
}
