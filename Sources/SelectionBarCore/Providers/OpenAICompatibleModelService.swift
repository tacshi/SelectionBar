import Foundation

public enum OpenAICompatibleModelService {
  public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  public struct FetchContext: Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var extraHeaders: [String: String]

    public init(baseURL: URL, apiKey: String, extraHeaders: [String: String] = [:]) {
      self.baseURL = baseURL
      self.apiKey = apiKey
      self.extraHeaders = extraHeaders
    }
  }

  public enum FetchError: LocalizedError, Equatable {
    case emptyAPIKey
    case invalidResponse
    case httpError(Int)
    case malformedResponse

    public var errorDescription: String? {
      switch self {
      case .emptyAPIKey:
        return "API key is empty."
      case .invalidResponse:
        return "Invalid response from server."
      case .httpError(let statusCode):
        return "Server returned HTTP \(statusCode)."
      case .malformedResponse:
        return "Unexpected model list response."
      }
    }
  }

  public static func fetchModels(
    context: FetchContext,
    dataLoader: DataLoader = { request in
      try await URLSession.shared.data(for: request)
    }
  ) async throws -> [String] {
    let apiKey = context.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else { throw FetchError.emptyAPIKey }

    let url = context.baseURL.appending(path: "models")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    for (key, value) in context.extraHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let (data, response) = try await dataLoader(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw FetchError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
      throw FetchError.httpError(httpResponse.statusCode)
    }

    let payload = try JSONDecoder().decode(ModelsResponse.self, from: data)
    let modelIDs = payload.data.map(\.id).filter { !$0.isEmpty }
    guard !modelIDs.isEmpty else {
      throw FetchError.malformedResponse
    }
    return Array(Set(modelIDs)).sorted()
  }
}

private struct ModelsResponse: Decodable {
  let data: [Model]

  struct Model: Decodable {
    let id: String
  }
}
