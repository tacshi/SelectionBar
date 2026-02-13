import Foundation
import Testing

@testable import SelectionBarCore

@Suite("OpenAI Client Streaming Tests")
struct OpenAIClientStreamingTests {
  @Test("OpenAIStreamingChunk decodes correctly")
  func chunkDecoding() throws {
    let json = #"{"choices":[{"delta":{"content":"Hello"}}]}"#
    let chunk = try JSONDecoder().decode(OpenAIStreamingChunk.self, from: Data(json.utf8))
    #expect(chunk.choices.count == 1)
    #expect(chunk.choices.first?.delta.content == "Hello")
  }

  @Test("OpenAIStreamingChunk decodes nil content")
  func chunkDecodingNilContent() throws {
    let json = #"{"choices":[{"delta":{}}]}"#
    let chunk = try JSONDecoder().decode(OpenAIStreamingChunk.self, from: Data(json.utf8))
    #expect(chunk.choices.first?.delta.content == nil)
  }

  @Test("OpenAIStreamingChunk decodes empty choices")
  func chunkDecodingEmptyChoices() throws {
    let json = #"{"choices":[]}"#
    let chunk = try JSONDecoder().decode(OpenAIStreamingChunk.self, from: Data(json.utf8))
    #expect(chunk.choices.isEmpty)
  }

  @Test("OpenAIStreamingChunk decodes tool call delta")
  func chunkDecodingToolCallDelta() throws {
    let json =
      #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_123","type":"function","function":{"name":"read_source","arguments":"{}"}}]}}]}"#
    let chunk = try JSONDecoder().decode(OpenAIStreamingChunk.self, from: Data(json.utf8))
    let delta = chunk.choices.first?.delta.toolCalls?.first
    #expect(delta?.index == 0)
    #expect(delta?.id == "call_123")
    #expect(delta?.function?.name == "read_source")
    #expect(delta?.function?.arguments == "{}")
  }

  @Test("streamCompletion parses SSE and yields tokens")
  func streamCompletionParsesSSE() async throws {
    let ssePayload = """
      data: {"choices":[{"delta":{"content":"Hello"}}]}

      data: {"choices":[{"delta":{"content":" World"}}]}

      data: [DONE]

      """

    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "test-key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )

    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key",
      modelId: "test-model",
      extraHeaders: [:]
    )

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try Data(ssePayload.utf8).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      let (bytes, _) = try await URLSession.shared.bytes(from: tempURL)
      let response = HTTPURLResponse(
        url: tempURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (bytes, response as URLResponse)
    }

    let stream = client.streamCompletion(
      messages: [.init(role: "user", content: "test")],
      context: context,
      temperature: 0.7,
      bytesLoader: bytesLoader
    )

    var tokens: [String] = []
    for try await event in stream {
      if case .content(let token) = event {
        tokens.append(token)
      }
    }

    #expect(tokens == ["Hello", " World"])
  }

  @Test("streamCompletion handles HTTP error")
  func streamCompletionHTTPError() async {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "test-key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )

    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key",
      modelId: "test-model",
      extraHeaders: [:]
    )

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try? Data("error".utf8).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      let (bytes, _) = try await URLSession.shared.bytes(from: tempURL)
      let response = HTTPURLResponse(
        url: tempURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
      return (bytes, response as URLResponse)
    }

    let stream = client.streamCompletion(
      messages: [.init(role: "user", content: "test")],
      context: context,
      temperature: 0.7,
      bytesLoader: bytesLoader
    )

    do {
      for try await _ in stream {
        Issue.record("Should not yield any tokens")
      }
      Issue.record("Should have thrown an error")
    } catch let error as SelectionBarError {
      if case .httpError(let code, _) = error {
        #expect(code == 401)
      } else {
        Issue.record("Expected httpError but got \(error)")
      }
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("streamCompletion skips non-data lines")
  func streamCompletionSkipsNonDataLines() async throws {
    let ssePayload = """
      : comment line
      event: ping

      data: {"choices":[{"delta":{"content":"token"}}]}

      data: [DONE]

      """

    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "test-key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )

    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key",
      modelId: "test-model",
      extraHeaders: [:]
    )

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try Data(ssePayload.utf8).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      let (bytes, _) = try await URLSession.shared.bytes(from: tempURL)
      let response = HTTPURLResponse(
        url: tempURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (bytes, response as URLResponse)
    }

    let stream = client.streamCompletion(
      messages: [.init(role: "user", content: "test")],
      context: context,
      temperature: 0.7,
      bytesLoader: bytesLoader
    )

    var tokens: [String] = []
    for try await event in stream {
      if case .content(let token) = event {
        tokens.append(token)
      }
    }

    #expect(tokens == ["token"])
  }

  @Test("streamCompletion yields tool calls from SSE")
  func streamCompletionYieldsToolCalls() async throws {
    let ssePayload = """
      data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"read_source","arguments":""}}]}}]}

      data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}

      data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

      data: [DONE]

      """

    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "test-key" },
      dataLoader: { _ in (Data(), URLResponse()) }
    )

    let context = OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key",
      modelId: "test-model",
      extraHeaders: [:]
    )

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try Data(ssePayload.utf8).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bytesLoader: SelectionBarOpenAIClient.BytesLoader = { _ in
      let (bytes, _) = try await URLSession.shared.bytes(from: tempURL)
      let response = HTTPURLResponse(
        url: tempURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (bytes, response as URLResponse)
    }

    let stream = client.streamCompletion(
      messages: [.init(role: "user", content: "test")],
      context: context,
      temperature: 0.7,
      bytesLoader: bytesLoader
    )

    var toolCalls: [ToolCall] = []
    for try await event in stream {
      if case .toolCall(let tc) = event {
        toolCalls.append(tc)
      }
    }

    #expect(toolCalls.count == 1)
    #expect(toolCalls.first?.id == "call_abc")
    #expect(toolCalls.first?.function.name == "read_source")
    #expect(toolCalls.first?.function.arguments == "{}")
  }
}
