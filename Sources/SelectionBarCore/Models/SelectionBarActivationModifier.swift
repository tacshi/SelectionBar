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
      return "Command"
    case .option:
      return "Option"
    case .control:
      return "Control"
    case .shift:
      return "Shift"
    }
  }
}
