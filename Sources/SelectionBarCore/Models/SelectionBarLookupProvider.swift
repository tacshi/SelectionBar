import Foundation

/// Dictionary app target for the Selection Bar look-up action.
public enum SelectionBarLookupProvider: String, CaseIterable, Codable, Sendable {
  case systemDictionary = "system-dictionary"
  case eudic = "eudic"
  case customApp = "custom-app"
}
