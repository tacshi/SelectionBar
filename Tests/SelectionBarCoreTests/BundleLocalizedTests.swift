import Foundation
import Testing

@testable import SelectionBarCore

@Suite("Bundle Localized Tests")
struct BundleLocalizedTests {
  @Test("Regional language preferences resolve to available localization")
  func resolvesRegionalLanguagePreference() {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans", "zh-Hant"],
      preferredLanguages: ["zh-Hans-CN"]
    )
    #expect(resolved == "zh-Hans")
  }

  @Test(
    "Traditional Chinese preferences resolve for Hong Kong and Taiwan",
    arguments: ["zh-Hant", "zh-Hant-HK", "zh-HK", "zh-Hant-TW", "zh-TW"]
  )
  func resolvesTraditionalChinesePreference(language: String) {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans", "zh-Hant"],
      preferredLanguages: [language]
    )
    #expect(resolved == "zh-Hant")
  }

  @Test("Exact language preferences still resolve normally")
  func resolvesExactLanguagePreference() {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans", "zh-Hant"],
      preferredLanguages: ["ja"]
    )
    #expect(resolved == "ja")
  }

  @Test("Unsupported languages fall back to source language")
  func fallsBackForUnsupportedLanguage() {
    let resolved = Bundle.resolvedLocalization(
      from: ["en", "ja", "zh-Hans", "zh-Hant"],
      preferredLanguages: ["fr-FR"]
    )
    #expect(resolved == "en")
  }
}
