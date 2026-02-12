import Foundation

public struct TranslationLanguageOption: Identifiable, Hashable, Sendable {
  public let code: String
  public let name: String
  public let nativeName: String?

  public var id: String { code }

  public init(code: String, name: String, nativeName: String? = nil) {
    self.code = code
    self.name = name
    self.nativeName = nativeName
  }

  public var localizedName: String {
    Locale.current.localizedString(forIdentifier: code) ?? name
  }
}

public enum TranslationLanguageCatalog {
  public static let defaultTargetLanguage = "en"

  public static let targetLanguages: [TranslationLanguageOption] = [
    TranslationLanguageOption(code: "en", name: "English"),
    TranslationLanguageOption(code: "zh-Hans", name: "Chinese (Simplified)", nativeName: "简体中文"),
    TranslationLanguageOption(code: "zh-Hant", name: "Chinese (Traditional)", nativeName: "繁體中文"),
    TranslationLanguageOption(code: "ja", name: "Japanese", nativeName: "日本語"),
    TranslationLanguageOption(code: "ko", name: "Korean", nativeName: "한국어"),
    TranslationLanguageOption(code: "es", name: "Spanish", nativeName: "Espanol"),
    TranslationLanguageOption(code: "fr", name: "French", nativeName: "Francais"),
    TranslationLanguageOption(code: "de", name: "German", nativeName: "Deutsch"),
    TranslationLanguageOption(code: "it", name: "Italian", nativeName: "Italiano"),
    TranslationLanguageOption(code: "pt", name: "Portuguese", nativeName: "Portugues"),
    TranslationLanguageOption(code: "ru", name: "Russian", nativeName: "Russkiy"),
    TranslationLanguageOption(code: "ar", name: "Arabic"),
    TranslationLanguageOption(code: "hi", name: "Hindi"),
    TranslationLanguageOption(code: "vi", name: "Vietnamese"),
    TranslationLanguageOption(code: "th", name: "Thai"),
    TranslationLanguageOption(code: "nl", name: "Dutch", nativeName: "Nederlands"),
    TranslationLanguageOption(code: "pl", name: "Polish", nativeName: "Polski"),
    TranslationLanguageOption(code: "tr", name: "Turkish", nativeName: "Turkce"),
    TranslationLanguageOption(code: "uk", name: "Ukrainian"),
    TranslationLanguageOption(code: "cs", name: "Czech"),
    TranslationLanguageOption(code: "sv", name: "Swedish"),
    TranslationLanguageOption(code: "da", name: "Danish"),
    TranslationLanguageOption(code: "fi", name: "Finnish"),
    TranslationLanguageOption(code: "el", name: "Greek"),
    TranslationLanguageOption(code: "he", name: "Hebrew"),
    TranslationLanguageOption(code: "id", name: "Indonesian"),
    TranslationLanguageOption(code: "ms", name: "Malay"),
  ]

  public static func contains(code: String) -> Bool {
    targetLanguages.contains { $0.code == code }
  }
}
