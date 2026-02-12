import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarActionHandler Tests")
@MainActor
struct SelectionBarActionHandlerTests {
  @Test("LLM process strips markdown code fences from provider output")
  func llmProcessSanitizesCodeFenceOutput() async throws {
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "openai-key" },
      dataLoader: { request in
        let json = #"{"choices":[{"message":{"content":"```json\n{\"result\":\"ok\"}\n```"}}]}"#
        return (Data(json.utf8), makeHTTPResponse(url: request.url!, statusCode: 200))
      }
    )

    let handler = SelectionBarActionHandler(
      openAIClient: client,
      lookupService: SelectionBarLookupService(),
      clipboardService: SelectionBarClipboardService()
    )

    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "Summarize",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      isEnabled: false
    )

    let output = try await handler.process(text: "input", action: action, settings: store)

    #expect(output == #"{"result":"ok"}"#)
  }

  @Test("JavaScript missing transform maps to SelectionBarError")
  func javaScriptMissingTransformErrorMapping() async {
    let handler = SelectionBarActionHandler()
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "JS",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "const noop = (x) => x;",
      isEnabled: false
    )

    do {
      _ = try await handler.process(text: "hello", action: action, settings: store)
      Issue.record("Expected javaScriptMissingTransform error")
    } catch let error as SelectionBarError {
      #expect(error == .javaScriptMissingTransform)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("JavaScript invalid return type maps to SelectionBarError")
  func javaScriptInvalidReturnTypeErrorMapping() async {
    let handler = SelectionBarActionHandler()
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "JS",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return 42; }",
      isEnabled: false
    )

    do {
      _ = try await handler.process(text: "hello", action: action, settings: store)
      Issue.record("Expected javaScriptInvalidReturnType error")
    } catch let error as SelectionBarError {
      #expect(error == .javaScriptInvalidReturnType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
