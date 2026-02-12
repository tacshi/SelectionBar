import Foundation
import Testing

@testable import SelectionBarCore

@Suite("OpenAICompatibleModelService Tests")
struct OpenAICompatibleModelServiceTests {
  final class RequestBox: @unchecked Sendable {
    private(set) var request: URLRequest?

    func set(_ request: URLRequest) {
      self.request = request
    }
  }

  @Test("fetchModels sends auth header and returns sorted unique model IDs")
  func fetchModelsSuccess() async throws {
    let context = OpenAICompatibleModelService.FetchContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key",
      extraHeaders: ["X-Title": "SelectionBar"]
    )

    let capture = RequestBox()

    let models = try await OpenAICompatibleModelService.fetchModels(context: context) { request in
      capture.set(request)
      let json = #"{"data":[{"id":"z-model"},{"id":"a-model"},{"id":"z-model"}]}"#
      let data = Data(json.utf8)
      return (data, makeHTTPResponse(url: request.url!, statusCode: 200))
    }

    #expect(capture.request?.url?.absoluteString == "https://api.example.com/v1/models")
    #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(capture.request?.value(forHTTPHeaderField: "X-Title") == "SelectionBar")
    #expect(models == ["a-model", "z-model"])
  }

  @Test("fetchModels fails for empty API key")
  func fetchModelsEmptyKey() async {
    let context = OpenAICompatibleModelService.FetchContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "   "
    )

    await #expect(throws: OpenAICompatibleModelService.FetchError.emptyAPIKey) {
      _ = try await OpenAICompatibleModelService.fetchModels(context: context) { _ in
        Issue.record("Data loader should not be called for empty API key")
        return (Data(), URLResponse())
      }
    }
  }

  @Test("fetchModels fails for non-200 HTTP status")
  func fetchModelsHTTPError() async {
    let context = OpenAICompatibleModelService.FetchContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key"
    )

    await #expect(throws: OpenAICompatibleModelService.FetchError.httpError(401)) {
      _ = try await OpenAICompatibleModelService.fetchModels(context: context) { request in
        (Data("{}".utf8), makeHTTPResponse(url: request.url!, statusCode: 401))
      }
    }
  }

  @Test("fetchModels fails for malformed payload")
  func fetchModelsMalformedPayload() async {
    let context = OpenAICompatibleModelService.FetchContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key"
    )

    await #expect(throws: OpenAICompatibleModelService.FetchError.malformedResponse) {
      _ = try await OpenAICompatibleModelService.fetchModels(context: context) { request in
        let json = #"{"data":[{"id":""}]}"#
        return (Data(json.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
      }
    }
  }

  @Test("fetchModels fails for non-HTTP response")
  func fetchModelsInvalidResponse() async {
    let context = OpenAICompatibleModelService.FetchContext(
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "test-key"
    )

    await #expect(throws: OpenAICompatibleModelService.FetchError.invalidResponse) {
      _ = try await OpenAICompatibleModelService.fetchModels(context: context) { _ in
        (Data(), URLResponse())
      }
    }
  }
}
