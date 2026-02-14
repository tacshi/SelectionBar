import Foundation

public struct ChatMessage: Identifiable, Sendable, Codable {
  public let id: UUID
  public let role: ChatMessageRole
  public var content: String

  public init(id: UUID = UUID(), role: ChatMessageRole, content: String) {
    self.id = id
    self.role = role
    self.content = content
  }
}

public enum ChatMessageRole: String, Sendable, Codable {
  case user
  case assistant
}
