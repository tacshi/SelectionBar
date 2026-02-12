import Foundation

public enum SelectionBarTranslationProviderKind: Sendable, Equatable {
  case app
  case llm
}

public struct SelectionBarTranslationProviderOption: Identifiable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let kind: SelectionBarTranslationProviderKind

  public init(id: String, name: String, kind: SelectionBarTranslationProviderKind) {
    self.id = id
    self.name = name
    self.kind = kind
  }
}

/// Built-in application providers for Selection Bar translation.
public enum SelectionBarTranslationAppProvider: String, CaseIterable, Sendable {
  case bob = "app-bob"
  case eudic = "app-eudic"

  public var displayName: String {
    switch self {
    case .bob: "Bob"
    case .eudic: "Eudic"
    }
  }

  public var bundleIDs: [String] {
    switch self {
    case .bob:
      return [
        "com.hezongyidev.Bob"
      ]
    case .eudic:
      return [
        "com.eusoft.eudic"
      ]
    }
  }

  public func translationURLCandidates(encodedQuery: String) -> [String] {
    switch self {
    case .bob:
      // Bob is handled specially via osascript in SelectionBarActionHandler.
      return []
    case .eudic:
      return [
        // Official Eudic URL scheme docs: eudic://dict/<word>
        "eudic://dict/\(encodedQuery)"
      ]
    }
  }
}
