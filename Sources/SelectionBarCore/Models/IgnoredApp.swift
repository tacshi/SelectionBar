import Foundation

/// An app that should be ignored by the selection bar.
public struct IgnoredApp: Codable, Identifiable, Equatable, Sendable {
  /// Bundle identifier (used as unique identity)
  public var id: String
  /// Display name shown in the UI
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}
