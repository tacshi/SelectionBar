import Foundation
import Testing

@testable import SelectionBarCore

@Suite("Bundle Localized Tests")
struct BundleLocalizedTests {
  @Test("Regional language preferences resolve to available localization")
  func resolvesRegionalLanguagePreference() {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans"],
      preferredLanguages: ["zh-Hans-CN"]
    )
    #expect(resolved == "zh-Hans")
  }

  @Test("Exact language preferences still resolve normally")
  func resolvesExactLanguagePreference() {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans"],
      preferredLanguages: ["ja"]
    )
    #expect(resolved == "ja")
  }

  @Test("Unsupported languages fall back to source language")
  func fallsBackForUnsupportedLanguage() {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans"],
      preferredLanguages: ["fr-FR"]
    )
    #expect(resolved == "en")
  }
}
