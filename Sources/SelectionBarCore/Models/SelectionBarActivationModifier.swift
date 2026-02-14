import Foundation

/// Modifier key that can be required while selecting text to show Selection Bar.
public enum SelectionBarActivationModifier: String, CaseIterable, Codable, Sendable {
  case command
  case option
  case control
  case shift

  public var displayName: String {
    switch self {
    case .command:
      return String(localized: "Command", bundle: .localizedModule)
    case .option:
      return String(localized: "Option", bundle: .localizedModule)
    case .control:
      return String(localized: "Control", bundle: .localizedModule)
    case .shift:
      return String(localized: "Shift", bundle: .localizedModule)
    }
  }
}
