import Foundation
import Testing

@testable import SelectionBarCore

@Suite("ChatMessage Tests")
struct ChatMessageTests {
  @Test("ChatMessage creation with default id")
  func messageCreation() {
    let message = ChatMessage(role: .user, content: "Hello")
    #expect(message.role == .user)
    #expect(message.content == "Hello")
    #expect(!message.id.uuidString.isEmpty)
  }

  @Test("ChatMessage creation with explicit id")
  func messageCreationWithId() {
    let id = UUID()
    let message = ChatMessage(id: id, role: .assistant, content: "Response")
    #expect(message.id == id)
    #expect(message.role == .assistant)
    #expect(message.content == "Response")
  }

  @Test("ChatMessageRole raw values")
  func roleRawValues() {
    #expect(ChatMessageRole.user.rawValue == "user")
    #expect(ChatMessageRole.assistant.rawValue == "assistant")
  }

  @Test("ChatMessage identities are unique")
  func uniqueIdentities() {
    let m1 = ChatMessage(role: .user, content: "a")
    let m2 = ChatMessage(role: .user, content: "a")
    #expect(m1.id != m2.id)
  }
}
