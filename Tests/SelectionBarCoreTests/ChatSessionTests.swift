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

  // MARK: - parseMaxChars

  @Test("parseMaxChars defaults to 5000 for empty arguments")
  func parseMaxCharsDefault() {
    #expect(ChatSession.parseMaxChars(from: "") == 5000)
  }

  @Test("parseMaxChars defaults to 5000 for invalid JSON")
  func parseMaxCharsInvalidJSON() {
    #expect(ChatSession.parseMaxChars(from: "not json") == 5000)
  }

  @Test("parseMaxChars clamps minimum to 500", arguments: [100, 0, -1])
  func parseMaxCharsMinClamp(value: Int) {
    let args = #"{"max_chars": \#(value)}"#
    #expect(ChatSession.parseMaxChars(from: args) == 500)
  }

  @Test("parseMaxChars clamps maximum to 20000", arguments: [50000, 20001])
  func parseMaxCharsMaxClamp(value: Int) {
    let args = #"{"max_chars": \#(value)}"#
    #expect(ChatSession.parseMaxChars(from: args) == 20000)
  }

  @Test("parseMaxChars passes through valid values", arguments: [500, 5000, 10000, 20000])
  func parseMaxCharsValid(value: Int) {
    let args = #"{"max_chars": \#(value)}"#
    #expect(ChatSession.parseMaxChars(from: args) == value)
  }

  // MARK: - extractPageExcerpt

  @Test("extractPageExcerpt centers around selected text")
  func extractPageExcerptCenters() {
    // 100 a's + "TARGET" + 100 b's = 206 chars total
    let content = String(repeating: "a", count: 100) + "TARGET" + String(repeating: "b", count: 100)
    let result = ChatSession.extractPageExcerpt(
      content: content, selectedText: "TARGET", maxChars: 50)
    // Should contain TARGET and surrounding context
    #expect(result.contains("TARGET"))
    #expect(result.contains("showing chars"))
  }

  @Test("extractPageExcerpt falls back to start when selected text not found")
  func extractPageExcerptFallback() {
    let content = String(repeating: "x", count: 200)
    let result = ChatSession.extractPageExcerpt(
      content: content, selectedText: "NOTFOUND", maxChars: 50)
    #expect(result.contains("showing first 50 chars"))
  }

  @Test("extractPageExcerpt falls back to start when selected text is empty")
  func extractPageExcerptEmptySelection() {
    let content = String(repeating: "x", count: 200)
    let result = ChatSession.extractPageExcerpt(
      content: content, selectedText: "", maxChars: 50)
    #expect(result.contains("showing first 50 chars"))
  }

  @Test("extractPageExcerpt clamps start to 0 when selection near beginning")
  func extractPageExcerptNearStart() {
    let content = "TARGET" + String(repeating: "x", count: 500)
    let result = ChatSession.extractPageExcerpt(
      content: content, selectedText: "TARGET", maxChars: 100)
    #expect(result.contains("showing chars 0–"))
  }

  @Test("extractPageExcerpt clamps end to content length when selection near end")
  func extractPageExcerptNearEnd() {
    let content = String(repeating: "x", count: 500) + "TARGET"
    let result = ChatSession.extractPageExcerpt(
      content: content, selectedText: "TARGET", maxChars: 100)
    #expect(result.contains("506 total chars"))
    #expect(result.contains("TARGET"))
  }

  @Test("extractPageExcerpt returns full content when maxChars exceeds length")
  func extractPageExcerptFullContent() {
    let content = "short content"
    let result = ChatSession.extractPageExcerpt(
      content: content, selectedText: "short", maxChars: 10000)
    #expect(result.contains("short content"))
  }

  // MARK: - parsePDFPageRange

  @Test("parsePDFPageRange returns nil for invalid JSON")
  func parsePDFPageRangeInvalid() {
    #expect(ChatSession.parsePDFPageRange(from: "bad") == nil)
  }

  @Test("parsePDFPageRange returns nil for missing fields")
  func parsePDFPageRangeMissing() {
    #expect(ChatSession.parsePDFPageRange(from: #"{"page_start": 1}"#) == nil)
  }

  @Test("parsePDFPageRange parses valid range")
  func parsePDFPageRangeValid() {
    let range = ChatSession.parsePDFPageRange(from: #"{"page_start": 2, "page_end": 5}"#)
    #expect(range?.start == 2)
    #expect(range?.end == 5)
  }

  // MARK: - formatPDFPages

  @Test("formatPDFPages clamps range to valid bounds")
  func formatPDFPagesClamp() {
    let result = ChatSession.formatPDFPages(
      pageStart: 0, pageEnd: 100, totalPages: 3,
      pageTextProvider: { _ in "text" }
    )
    #expect(result.hasPrefix("Pages 1-3 of 3:"))
  }

  @Test("formatPDFPages returns error for reversed range")
  func formatPDFPagesReversed() {
    let result = ChatSession.formatPDFPages(
      pageStart: 5, pageEnd: 2, totalPages: 10,
      pageTextProvider: { _ in "text" }
    )
    #expect(result.contains("Error: page_start (5) must be <= page_end (2)."))
  }

  @Test("formatPDFPages uses (empty page) for nil page text")
  func formatPDFPagesEmptyPage() {
    let result = ChatSession.formatPDFPages(
      pageStart: 1, pageEnd: 1, totalPages: 1,
      pageTextProvider: { _ in nil }
    )
    #expect(result.contains("(empty page)"))
  }

  @Test("formatPDFPages formats multiple pages with separators")
  func formatPDFPagesMultiple() {
    let result = ChatSession.formatPDFPages(
      pageStart: 1, pageEnd: 2, totalPages: 5,
      pageTextProvider: { i in "Page \(i) content" }
    )
    #expect(result.contains("--- Page 1 ---"))
    #expect(result.contains("--- Page 2 ---"))
    #expect(result.contains("Page 1 content"))
    #expect(result.contains("Page 2 content"))
    #expect(result.hasPrefix("Pages 1-2 of 5:"))
  }

  // MARK: - parseSourceLineRange

  @Test("parseSourceLineRange returns nil for invalid JSON")
  func parseSourceLineRangeInvalid() {
    #expect(ChatSession.parseSourceLineRange(from: "bad") == nil)
  }

  @Test("parseSourceLineRange returns nil for missing fields")
  func parseSourceLineRangeMissing() {
    #expect(ChatSession.parseSourceLineRange(from: #"{"line_start": 1}"#) == nil)
  }

  @Test("parseSourceLineRange parses valid range")
  func parseSourceLineRangeValid() {
    let range = ChatSession.parseSourceLineRange(from: #"{"line_start": 3, "line_end": 7}"#)
    #expect(range?.start == 3)
    #expect(range?.end == 7)
  }

  // MARK: - formatSourceLines

  @Test("formatSourceLines returns numbered lines")
  func formatSourceLinesNumbered() {
    let lines = ["alpha", "beta", "gamma", "delta"]
    let result = ChatSession.formatSourceLines(lineStart: 2, lineEnd: 3, allLines: lines)
    #expect(result.contains("2:beta"))
    #expect(result.contains("3:gamma"))
    #expect(result.hasPrefix("Lines 2-3 of 4:"))
  }

  @Test("formatSourceLines clamps to valid range")
  func formatSourceLinesClamped() {
    let lines = ["a", "b", "c"]
    let result = ChatSession.formatSourceLines(lineStart: 0, lineEnd: 100, allLines: lines)
    #expect(result.hasPrefix("Lines 1-3 of 3:"))
    #expect(result.contains("1:a"))
    #expect(result.contains("3:c"))
  }

  @Test("formatSourceLines returns error for reversed range")
  func formatSourceLinesReversed() {
    let lines = ["a", "b", "c"]
    let result = ChatSession.formatSourceLines(lineStart: 5, lineEnd: 2, allLines: lines)
    #expect(result.contains("Error: line_start (5) must be <= line_end (2)."))
  }

  // MARK: - Restored messages

  @Test("restoredMessages populates messages array")
  func restoredMessages() {
    let restored = [
      ChatMessage(role: .user, content: "Previous question"),
      ChatMessage(role: .assistant, content: "Previous answer"),
    ]
    let session = ChatSession(
      selectedText: "test",
      client: makeClient(),
      context: makeContext(),
      restoredMessages: restored
    )
    #expect(session.messages.count == 2)
    #expect(session.messages[0].role == .user)
    #expect(session.messages[0].content == "Previous question")
    #expect(session.messages[1].role == .assistant)
    #expect(session.messages[1].content == "Previous answer")
  }

  @Test("restoredMessages defaults to empty")
  func restoredMessagesDefault() {
    let session = ChatSession(
      selectedText: "test",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.messages.isEmpty)
  }

  // MARK: - onStreamingComplete

  @Test("onStreamingComplete callback can be set")
  func onStreamingCompleteCallback() {
    let session = ChatSession(
      selectedText: "test",
      client: makeClient(),
      context: makeContext()
    )
    #expect(session.onStreamingComplete == nil)

    var called = false
    session.onStreamingComplete = { called = true }
    session.onStreamingComplete?()
    #expect(called)
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
