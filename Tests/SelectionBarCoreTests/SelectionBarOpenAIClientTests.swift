import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarOpenAIClient Tests")
struct SelectionBarOpenAIClientTests {
  struct RequestCapture: @unchecked Sendable {
    var models: [String] = []
    var urls: [URL] = []
    var bodies: [[String: Any]] = []
  }

  final class CaptureBox: @unchecked Sendable {
    private(set) var value = RequestCapture()

    func appendURL(_ url: URL) {
      value.urls.append(url)
    }

    func appendBody(_ body: [String: Any]) {
      value.bodies.append(body)
    }

    func appendModel(_ model: String) {
      value.models.append(model)
    }
  }

  @Test("complete prioritizes explicit model over translation/default model")
  func completionModelSelectionPriority() async throws {
    let capture = CaptureBox()

    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "test-key" },
      dataLoader: { request in
        if let url = request.url {
          capture.appendURL(url)
        }
        if let bodyData = request.httpBody,
          let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        {
          capture.appendBody(body)
          if let model = body["model"] as? String {
            capture.appendModel(model)
          }
        }

        let json = #"{"choices":[{"message":{"content":"ok"}}]}"#
        let data = Data(json.utf8)
        return (data, makeHTTPResponse(url: request.url!, statusCode: 200))
      }
    )

    let snapshot = SelectionBarProviderSettingsSnapshot(
      openAIModel: "gpt-default",
      openAITranslationModel: "gpt-translate",
      openRouterModel: "or-default",
      openRouterTranslationModel: "or-translate",
      customLLMProviders: []
    )

    _ = try await client.complete(
      prompt: "first",
      providerId: "openai",
      explicitModelId: "",
      preferTranslationModel: true,
      settingsSnapshot: snapshot,
      temperature: 0.2
    )

    _ = try await client.complete(
      prompt: "second",
      providerId: "openai",
      explicitModelId: "gpt-explicit",
      preferTranslationModel: true,
      settingsSnapshot: snapshot,
      temperature: 0.2
    )

    #expect(capture.value.urls.count == 2)
    #expect(
      capture.value.urls.allSatisfy {
        $0.absoluteString == "https://api.openai.com/v1/chat/completions"
      })
    #expect(capture.value.models == ["gpt-translate", "gpt-explicit"])
  }

  @Test("complete uses custom provider translation model and fails when key is missing")
  func customProviderModelAndKeyAvailability() async throws {
    let provider = CustomLLMProvider(
      id: UUID(),
      name: "Custom",
      baseURL: URL(string: "https://custom.example.com/v1")!,
      capabilities: [.llm, .translation],
      llmModel: "custom-chat",
      translationModel: "custom-translate"
    )

    let capture = CaptureBox()

    let successClient = SelectionBarOpenAIClient(
      apiKeyReader: { key in
        key == provider.keychainKey ? "provider-key" : ""
      },
      dataLoader: { request in
        if let bodyData = request.httpBody,
          let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
          let model = body["model"] as? String
        {
          capture.appendModel(model)
        }
        let json = #"{"choices":[{"message":{"content":"ok"}}]}"#
        return (Data(json.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
      }
    )

    let snapshot = SelectionBarProviderSettingsSnapshot(
      openAIModel: "",
      openAITranslationModel: "",
      openRouterModel: "",
      openRouterTranslationModel: "",
      customLLMProviders: [provider]
    )

    _ = try await successClient.complete(
      prompt: "translate",
      providerId: provider.providerId,
      explicitModelId: "",
      preferTranslationModel: true,
      settingsSnapshot: snapshot,
      temperature: 0.1
    )

    #expect(capture.value.models == ["custom-translate"])

    let missingKeyClient = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "" },
      dataLoader: { _ in
        Issue.record("No network call should happen when API key is missing")
        return (Data(), URLResponse())
      }
    )

    do {
      _ = try await missingKeyClient.complete(
        prompt: "x",
        providerId: provider.providerId,
        explicitModelId: "",
        preferTranslationModel: true,
        settingsSnapshot: snapshot,
        temperature: 0.1
      )
      Issue.record("Expected providerUnavailable error")
    } catch let error as SelectionBarError {
      if case .providerUnavailable(let providerID) = error {
        #expect(providerID == provider.providerId)
      } else {
        Issue.record("Unexpected SelectionBarError: \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("translateWithDeepL normalizes Chinese target codes and chooses free endpoint for :fx key")
  func deepLNormalizationAndEndpointSelection() async throws {
    let capture = CaptureBox()

    let client = SelectionBarOpenAIClient(
      apiKeyReader: { key in
        key == "deepl_api_key" ? "deepl-key:fx" : ""
      },
      dataLoader: { request in
        if let url = request.url {
          capture.appendURL(url)
        }
        if let bodyData = request.httpBody,
          let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        {
          capture.appendBody(body)
        }

        let json = #"{"translations":[{"text":"你好"}]}"#
        return (Data(json.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
      }
    )

    let translated = try await client.translateWithDeepL(
      text: "hello", targetLanguageCode: "zh-Hans")

    #expect(translated == "你好")
    #expect(capture.value.urls.first?.host == "api-free.deepl.com")
    #expect(capture.value.bodies.first?["target_lang"] as? String == "ZH")
  }

  @Test("complete decodes both string and parts content payload formats")
  func completionResponseDecodingVariants() async throws {
    let responses = [
      #"{"choices":[{"message":{"content":"plain-text"}}]}"#,
      #"{"choices":[{"message":{"content":[{"type":"text","text":"part-1"},{"type":"text","text":"+part-2"}]}}]}"#,
    ]

    let index = ManagedAtomicInt(0)

    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "openai-key" },
      dataLoader: { request in
        let current = index.incrementAndGet() - 1
        let payload = responses[current]
        return (Data(payload.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
      }
    )

    let snapshot = SelectionBarProviderSettingsSnapshot(
      openAIModel: "gpt-4o-mini",
      openAITranslationModel: "",
      openRouterModel: "",
      openRouterTranslationModel: "",
      customLLMProviders: []
    )

    let plain = try await client.complete(
      prompt: "first",
      providerId: "openai",
      explicitModelId: "",
      preferTranslationModel: false,
      settingsSnapshot: snapshot,
      temperature: 0.2
    )
    #expect(plain == "plain-text")

    let parts = try await client.complete(
      prompt: "second",
      providerId: "openai",
      explicitModelId: "",
      preferTranslationModel: false,
      settingsSnapshot: snapshot,
      temperature: 0.2
    )
    #expect(parts == "part-1+part-2")
  }
}

private final class ManagedAtomicInt: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int

  init(_ initialValue: Int) {
    value = initialValue
  }

  func incrementAndGet() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }
}
