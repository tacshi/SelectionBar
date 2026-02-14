import Foundation
import Testing

@testable import SelectionBarCore

@Suite("ChatSession Tests")
@MainActor
struct ChatSessionTests {
  @Test("Initial state is empty")
  func initialState() {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )
    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "key",
      modelId: "model",
      extraHeaders: [:]
    )
    let session = ChatSession(selectedText: "test", client: client, context: context)
    #expect(session.messages.isEmpty)
    #expect(!session.isStreaming)
    #expect(session.currentStreamingContent == "")
    #expect(session.error == nil)
  }

  @Test("sendMessage does not accept empty text")
  func emptyMessage() {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )
    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "key",
      modelId: "model",
      extraHeaders: [:]
    )
    let session = ChatSession(selectedText: "test", client: client, context: context)
    session.sendMessage("   ")
    #expect(session.messages.isEmpty)
    #expect(!session.isStreaming)
  }

  @Test("sendMessage appends user message and starts streaming")
  func sendMessageStartsStreaming() {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )
    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "key",
      modelId: "model",
      extraHeaders: [:]
    )

    // Use a bytes loader that hangs so we can observe state
    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      // Hang indefinitely until cancelled
      try await Task.sleep(for: .seconds(100))
      throw CancellationError()
    }

    let session = ChatSession(
      selectedText: "test", client: client, context: context, bytesLoader: bytesLoader)
    session.sendMessage("Hello")

    #expect(session.messages.count == 2)
    #expect(session.messages[0].role == .user)
    #expect(session.messages[0].content == "Hello")
    #expect(session.messages[1].role == .assistant)
    #expect(session.isStreaming)

    session.cancelStreaming()
  }

  @Test("reset clears all state")
  func resetClearsState() {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )
    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "key",
      modelId: "model",
      extraHeaders: [:]
    )
    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      try await Task.sleep(for: .seconds(100))
      throw CancellationError()
    }

    let session = ChatSession(
      selectedText: "test", client: client, context: context, bytesLoader: bytesLoader)
    session.sendMessage("Hello")
    #expect(!session.messages.isEmpty)

    session.reset()
    #expect(session.messages.isEmpty)
    #expect(!session.isStreaming)
    #expect(session.currentStreamingContent == "")
    #expect(session.error == nil)
  }

  @Test("cancelStreaming stops streaming state")
  func cancelStreaming() {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )
    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "key",
      modelId: "model",
      extraHeaders: [:]
    )
    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      try await Task.sleep(for: .seconds(100))
      throw CancellationError()
    }

    let session = ChatSession(
      selectedText: "test", client: client, context: context, bytesLoader: bytesLoader)
    session.sendMessage("Hello")
    #expect(session.isStreaming)

    session.cancelStreaming()
    #expect(!session.isStreaming)
  }

  // MARK: - Source kind detection

  @Test("sourceKind returns .file for local file path")
  func sourceKindFile() {
    let session = ChatSession(
      selectedText: "test",
      sourceURL: "/Users/test/document.txt",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.sourceKind == .file)
  }

  @Test("sourceKind returns .webPage for browser URL with known bundle ID")
  func sourceKindWebPage() {
    let session = ChatSession(
      selectedText: "test",
      sourceURL: "https://example.com/page",
      sourceBundleID: "com.google.Chrome",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.sourceKind == .webPage)
  }

  @Test("sourceKind returns nil for browser URL with unknown bundle ID")
  func sourceKindUnknownBrowser() {
    let session = ChatSession(
      selectedText: "test",
      sourceURL: "https://example.com/page",
      sourceBundleID: "com.unknown.app",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.sourceKind == nil)
  }

  @Test("sourceKind returns nil when no source URL")
  func sourceKindNoSource() {
    let session = ChatSession(
      selectedText: "test",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.sourceKind == nil)
  }

  @Test("sourceKind returns .webPage for http URL")
  func sourceKindHttpURL() {
    let session = ChatSession(
      selectedText: "test",
      sourceURL: "http://example.com/page",
      sourceBundleID: "com.apple.Safari",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.sourceKind == .webPage)
  }

  @Test("sourceKind returns nil for browser URL without bundle ID")
  func sourceKindNoBundleID() {
    let session = ChatSession(
      selectedText: "test",
      sourceURL: "https://example.com/page",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.sourceKind == nil)
  }

  // MARK: - Helpers

  private func makeClient() -> SelectionBarOpenAIClient {
    SelectionBarOpenAIClient(
      apiKeyReader: { _ in "key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )
  }

  private func makeContext() -> OpenAICompatibleCompletionContext {
    OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "key",
      modelId: "model",
      extraHeaders: [:]
    )
  }
}
