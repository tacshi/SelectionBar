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

  @Test("Key binding with invalid shortcut maps to SelectionBarError")
  func keyBindingInvalidShortcutErrorMapping() async {
    let handler = SelectionBarActionHandler()
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+",
      isEnabled: false
    )

    do {
      _ = try await handler.process(text: "hello", action: action, settings: store)
      Issue.record("Expected invalidKeyboardShortcut error")
    } catch let error as SelectionBarError {
      #expect(error == .invalidKeyboardShortcut("cmd+"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("run command uses configured terminal selection")
  func runCommandUsesConfiguredTerminalSelection() async throws {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)
    store.selectionBarTerminalApp = .ghostty

    var launchedText: String?

    let terminalService = SelectionBarTerminalCommandService(
      homeDirectoryProvider: { FileManager.default.temporaryDirectory },
      environmentProvider: { ["PATH": "/usr/bin"] },
      appURLResolver: { _, _ in
        FileManager.default.temporaryDirectory.appendingPathComponent("Ghostty.app")
      },
      appleScriptRunner: { request in
        launchedText = request.arguments.first
      },
      processRunner: { _ in },
      fileWriter: { _ in },
      urlOpener: { _ in true }
    )

    let handler = SelectionBarActionHandler(
      openAIClient: SelectionBarOpenAIClient(),
      lookupService: SelectionBarLookupService(),
      clipboardService: SelectionBarClipboardService(),
      terminalCommandService: terminalService
    )

    try await handler.runCommand(text: "/usr/bin/git status", settings: store)

    #expect(launchedText == "/usr/bin/git status")
    let canRunCommand = await handler.canRunCommand(text: "/usr/bin/git status", settings: store)
    #expect(canRunCommand)
  }

  @Test("run command visibility requires an available terminal app")
  func runCommandVisibilityRequiresAvailableTerminalApp() async {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)
    store.selectionBarTerminalApp = .ghostty

    let terminalService = SelectionBarTerminalCommandService(
      homeDirectoryProvider: { FileManager.default.temporaryDirectory },
      environmentProvider: { ["PATH": "/usr/bin"] },
      appURLResolver: { _, _ in nil }
    )

    let handler = SelectionBarActionHandler(
      openAIClient: SelectionBarOpenAIClient(),
      lookupService: SelectionBarLookupService(),
      clipboardService: SelectionBarClipboardService(),
      terminalCommandService: terminalService
    )

    let canRunCommand = await handler.canRunCommand(text: "/usr/bin/git status", settings: store)
    #expect(!canRunCommand)
  }
}
