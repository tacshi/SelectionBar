import Foundation

public enum GrammarRefinement: String, Codable, CaseIterable, Sendable {
  case grammar, clarity, rewrite

  public var displayName: String {
    switch self {
    case .grammar: String(localized: "Grammar only", bundle: .localizedModule)
    case .clarity: String(localized: "Improve clarity", bundle: .localizedModule)
    case .rewrite: String(localized: "Rewrite", bundle: .localizedModule)
    }
  }
}

public enum GrammarTone: String, Codable, CaseIterable, Sendable {
  case preserve, formal, casual

  public var displayName: String {
    switch self {
    case .preserve: String(localized: "Keep my tone", bundle: .localizedModule)
    case .formal: String(localized: "Formal", bundle: .localizedModule)
    case .casual: String(localized: "Casual", bundle: .localizedModule)
    }
  }
}

public struct GrammarWritingProfile: Codable, Equatable, Sendable {
  public var refinement: GrammarRefinement = .clarity
  public var tone: GrammarTone = .preserve

  public init(refinement: GrammarRefinement = .clarity, tone: GrammarTone = .preserve) {
    self.refinement = refinement
    self.tone = tone
  }

  private enum CodingKeys: String, CodingKey { case refinement, tone }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    refinement =
      GrammarRefinement(
        rawValue: try values.decodeIfPresent(String.self, forKey: .refinement) ?? "") ?? .clarity
    tone =
      GrammarTone(rawValue: try values.decodeIfPresent(String.self, forKey: .tone) ?? "")
      ?? .preserve
  }
}

public enum GrammarTriggerMode: String, Codable, CaseIterable, Sendable {
  case off, hotkey, automatic

  public var displayName: String {
    switch self {
    case .off: String(localized: "Off", bundle: .localizedModule)
    case .hotkey: String(localized: "Hotkey only", bundle: .localizedModule)
    case .automatic: String(localized: "Automatic + hotkey", bundle: .localizedModule)
    }
  }
}

public enum GrammarEnglishConvention: String, Codable, CaseIterable, Sendable {
  case both, british, american

  public var displayName: String {
    switch self {
    case .both: String(localized: "Accept both", bundle: .localizedModule)
    case .british: String(localized: "British English", bundle: .localizedModule)
    case .american: String(localized: "American English", bundle: .localizedModule)
    }
  }
}

public struct GrammarSettings: Codable, Equatable, Sendable {
  public var mode: GrammarTriggerMode = .off
  public var shortcut = ""
  public var providerID = ""
  public var modelID = ""
  public var englishConvention: GrammarEnglishConvention = .both
  public var excludedApps: [IgnoredApp] = []
  public var manualProfile = GrammarWritingProfile()
  public var showsUnderlines = true

  public init() {}

  private enum CodingKeys: String, CodingKey {
    case mode, shortcut, providerID, modelID, englishConvention, excludedApps, manualProfile,
      showsUnderlines
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    mode =
      GrammarTriggerMode(rawValue: try values.decodeIfPresent(String.self, forKey: .mode) ?? "")
      ?? .off
    shortcut = try values.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
    providerID = try values.decodeIfPresent(String.self, forKey: .providerID) ?? ""
    modelID = try values.decodeIfPresent(String.self, forKey: .modelID) ?? ""
    englishConvention =
      GrammarEnglishConvention(
        rawValue: try values.decodeIfPresent(String.self, forKey: .englishConvention) ?? "")
      ?? .both
    excludedApps = try values.decodeIfPresent([IgnoredApp].self, forKey: .excludedApps) ?? []
    manualProfile =
      try values.decodeIfPresent(GrammarWritingProfile.self, forKey: .manualProfile)
      ?? GrammarWritingProfile()
    showsUnderlines = try values.decodeIfPresent(Bool.self, forKey: .showsUnderlines) ?? true
  }
}
