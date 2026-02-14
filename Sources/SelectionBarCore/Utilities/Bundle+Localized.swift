import Foundation

extension Bundle {
  /// Returns the localized variant of the module bundle that matches the app's
  /// preferred language.  SPM sub-bundles loaded via `Bundle(path:)` don't
  /// automatically inherit `AppleLanguages` from `UserDefaults`, so we resolve
  /// the correct `.lproj` sub-bundle manually.
  static var localizedModule: Bundle {
    localizedModule(forPreferredLanguages: nil)
  }

  static func localizedModule(forPreferredLanguages preferredLanguages: [String]?) -> Bundle {
    let base = Bundle.module
    // Prefer app override (AppleLanguages), otherwise system language preferences.
    let languagePreferences =
      preferredLanguages
      ?? UserDefaults.standard.stringArray(forKey: "AppleLanguages")
      ?? Locale.preferredLanguages

    // Resolve regional language identifiers (e.g. zh-Hans-CN -> zh-Hans).
    guard
      let resolvedLocalization = resolvedLocalization(
        from: base.localizations,
        preferredLanguages: languagePreferences
      ),
      let path = base.path(forResource: resolvedLocalization, ofType: "lproj"),
      let localized = Bundle(path: path)
    else {
      return base
    }
    return localized
  }

  static func resolvedLocalization(
    from availableLocalizations: [String],
    preferredLanguages: [String]
  ) -> String? {
    Bundle.preferredLocalizations(
      from: availableLocalizations,
      forPreferences: preferredLanguages
    ).first
  }
}
