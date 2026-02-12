import Foundation

struct SelectionBarOpenAIClient: Sendable {
  typealias APIKeyReader = @Sendable (String) -> String
  typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private let apiKeyReader: APIKeyReader
  private let dataLoader: DataLoader

  init(
    apiKeyReader: @escaping APIKeyReader = { key in
      KeychainHelper.shared.readString(key: key) ?? ""
    },
    dataLoader: @escaping DataLoader = { request in
      try await URLSession.shared.data(for: request)
    }
  ) {
    self.apiKeyReader = apiKeyReader
    self.dataLoader = dataLoader
  }

  func complete(
    prompt: String,
    providerId: String,
    explicitModelId: String,
    preferTranslationModel: Bool,
    settingsSnapshot: SelectionBarProviderSettingsSnapshot,
    temperature: Double
  ) async throws -> String {
    let context = try resolveProviderContext(
      providerId: providerId,
      explicitModelId: explicitModelId,
      preferTranslationModel: preferTranslationModel,
      settingsSnapshot: settingsSnapshot
    )

    return try await performCompletion(
      prompt: prompt,
      context: context,
      temperature: temperature
    )
  }

  func translateWithDeepL(text: String, targetLanguageCode: String) async throws -> String {
    let apiKey = readAPIKey("deepl_api_key")
    guard !apiKey.isEmpty else { throw SelectionBarError.providerUnavailable("deepl") }

    let endpoint =
      apiKey.hasSuffix(":fx")
      ? URL(string: "https://api-free.deepl.com/v2/translate")!
      : URL(string: "https://api.deepl.com/v2/translate")!

    let deepLTarget = normalizedDeepLTargetCode(targetLanguageCode)
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      DeepLTranslateRequest(text: [text], targetLang: deepLTarget)
    )

    let (data, response) = try await dataLoader(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SelectionBarError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8)
      throw SelectionBarError.httpError(httpResponse.statusCode, body)
    }

    let parsed = try JSONDecoder().decode(DeepLTranslateResponse.self, from: data)
    guard
      let result = parsed.translations.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
      !result.isEmpty
    else {
      throw SelectionBarError.emptyResult
    }

    return result
  }

  private func normalizedDeepLTargetCode(_ code: String) -> String {
    switch code {
    case "zh-Hans", "zh-Hant":
      return "ZH"
    default:
      return code.uppercased()
    }
  }

  private func resolveProviderContext(
    providerId: String,
    explicitModelId: String,
    preferTranslationModel: Bool,
    settingsSnapshot: SelectionBarProviderSettingsSnapshot
  ) throws -> OpenAICompatibleCompletionContext {
    let trimmedModel = explicitModelId.trimmingCharacters(in: .whitespacesAndNewlines)

    if providerId == "openai" {
      let modelId =
        if !trimmedModel.isEmpty {
          trimmedModel
        } else if preferTranslationModel && !settingsSnapshot.openAITranslationModel.isEmpty {
          settingsSnapshot.openAITranslationModel
        } else {
          settingsSnapshot.openAIModel
        }
      return try openAIContext(modelId: modelId)
    }

    if providerId == "openrouter" {
      let modelId =
        if !trimmedModel.isEmpty {
          trimmedModel
        } else if preferTranslationModel && !settingsSnapshot.openRouterTranslationModel.isEmpty {
          settingsSnapshot.openRouterTranslationModel
        } else {
          settingsSnapshot.openRouterModel
        }
      return try openRouterContext(modelId: modelId)
    }

    guard providerId.hasPrefix("custom-"),
      let provider = settingsSnapshot.customLLMProviders.first(where: {
        $0.providerId == providerId
      })
    else {
      throw SelectionBarError.providerUnavailable(providerId)
    }

    let modelId =
      if !trimmedModel.isEmpty {
        trimmedModel
      } else if preferTranslationModel && !provider.translationModel.isEmpty {
        provider.translationModel
      } else {
        provider.llmModel
      }

    let apiKey = readAPIKey(provider.keychainKey)
    guard !apiKey.isEmpty else {
      throw SelectionBarError.providerUnavailable(providerId)
    }
    guard !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SelectionBarError.providerUnavailable(providerId)
    }

    return OpenAICompatibleCompletionContext(
      baseURL: provider.baseURL,
      apiKey: apiKey,
      modelId: modelId,
      extraHeaders: [:]
    )
  }

  private func openAIContext(modelId: String) throws -> OpenAICompatibleCompletionContext {
    let apiKey = readAPIKey("openai_api_key")
    guard !apiKey.isEmpty else { throw SelectionBarError.providerUnavailable("openai") }
    guard !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SelectionBarError.providerUnavailable("openai")
    }

    return OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://api.openai.com/v1")!,
      apiKey: apiKey,
      modelId: modelId,
      extraHeaders: [:]
    )
  }

  private func openRouterContext(modelId: String) throws -> OpenAICompatibleCompletionContext {
    let apiKey = readAPIKey("openrouter_api_key")
    guard !apiKey.isEmpty else { throw SelectionBarError.providerUnavailable("openrouter") }
    guard !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SelectionBarError.providerUnavailable("openrouter")
    }

    return OpenAICompatibleCompletionContext(
      baseURL: URL(string: "https://openrouter.ai/api/v1")!,
      apiKey: apiKey,
      modelId: modelId,
      extraHeaders: [
        "HTTP-Referer": "https://github.com/tacshi/SelectionBar",
        "X-Title": "SelectionBar",
      ]
    )
  }

  private func readAPIKey(_ key: String) -> String {
    let value = apiKeyReader(key)
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func performCompletion(
    prompt: String,
    context: OpenAICompatibleCompletionContext,
    temperature: Double
  ) async throws -> String {
    let url = context.baseURL.appending(path: "chat/completions")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    request.setValue("Bearer \(context.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    for (header, value) in context.extraHeaders {
      request.setValue(value, forHTTPHeaderField: header)
    }

    request.httpBody = try JSONEncoder().encode(
      OpenAICompatibleCompletionRequest(
        model: context.modelId,
        messages: [OpenAICompatibleCompletionRequest.Message(role: "user", content: prompt)],
        temperature: temperature
      )
    )

    let (data, response) = try await dataLoader(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SelectionBarError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8)
      throw SelectionBarError.httpError(httpResponse.statusCode, body)
    }

    let parsed = try JSONDecoder().decode(OpenAICompatibleCompletionResponse.self, from: data)
    guard let content = parsed.firstContent else {
      throw SelectionBarError.invalidResponse
    }

    return content
  }
}

struct SelectionBarProviderSettingsSnapshot: Sendable {
  let openAIModel: String
  let openAITranslationModel: String
  let openRouterModel: String
  let openRouterTranslationModel: String
  let customLLMProviders: [CustomLLMProvider]
}

private struct OpenAICompatibleCompletionContext {
  let baseURL: URL
  let apiKey: String
  let modelId: String
  let extraHeaders: [String: String]
}

private struct OpenAICompatibleCompletionRequest: Encodable {
  let model: String
  let messages: [Message]
  let temperature: Double

  struct Message: Encodable {
    let role: String
    let content: String
  }
}

private struct OpenAICompatibleCompletionResponse: Decodable {
  let choices: [Choice]

  var firstContent: String? {
    choices.first?.message.content.text
  }

  struct Choice: Decodable {
    let message: Message
  }

  struct Message: Decodable {
    let content: Content
  }

  enum Content: Decodable {
    case text(String)
    case parts([Part])

    var text: String {
      switch self {
      case .text(let value):
        value
      case .parts(let parts):
        parts.compactMap(\.text).joined()
      }
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let value = try? container.decode(String.self) {
        self = .text(value)
        return
      }
      if let value = try? container.decode([Part].self) {
        self = .parts(value)
        return
      }
      throw DecodingError.typeMismatch(
        Content.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unsupported message content format."
        )
      )
    }
  }

  struct Part: Decodable {
    let text: String?
  }
}

private struct DeepLTranslateRequest: Encodable {
  let text: [String]
  let targetLang: String

  enum CodingKeys: String, CodingKey {
    case text
    case targetLang = "target_lang"
  }
}

private struct DeepLTranslateResponse: Decodable {
  let translations: [Translation]

  struct Translation: Decodable {
    let text: String?
  }
}
