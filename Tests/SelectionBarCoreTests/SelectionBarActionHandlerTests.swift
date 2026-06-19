import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarActionHandler Tests")
@MainActor
struct SelectionBarActionHandlerTests {
  private final class CompletionCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPrompts: [String] = []
    private var storedRequestCount = 0

    var prompts: [String] {
      lock.lock()
      defer { lock.unlock() }
      return storedPrompts
    }

    var requestCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return storedRequestCount
    }

    func record(_ request: URLRequest) {
      let prompt =
        request.httpBody.flatMap { bodyData -> String? in
          guard
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let messages = body["messages"] as? [[String: Any]]
          else {
            return nil
          }
          return messages.first?["content"] as? String
        } ?? ""

      lock.lock()
      storedRequestCount += 1
      storedPrompts.append(prompt)
      lock.unlock()
    }
  }

  @Test("LLM prompt renderer substitutes source context variables")
  func llmPromptRendererSubstitutesSourceContextVariables() {
    let sourceContext = SelectionBarActionSourceContext(
      appName: "TextEdit",
      bundleID: "com.apple.TextEdit",
      sourceURL: "/tmp/note.txt",
      sourceKind: .textFile,
      excerpt: "Lines 1-2 of 2:\n1:alpha\n2:selected",
      isAvailable: true
    )

    let prompt = SelectionBarActionHandler.renderPrompt(
      template:
        "Text={{TEXT}}\nContext={{CONTEXT}}\nSource={{SOURCE_URL}}\nApp={{APP_NAME}}\nBundle={{BUNDLE_ID}}",
      text: "selected",
      sourceContext: sourceContext,
      includesSourceContext: true
    )

    #expect(prompt.contains("Text=selected"))
    #expect(prompt.contains("Source Context:"))
    #expect(prompt.contains("Lines 1-2 of 2"))
    #expect(prompt.contains("Source=/tmp/note.txt"))
    #expect(prompt.contains("App=TextEdit"))
    #expect(prompt.contains("Bundle=com.apple.TextEdit"))
    #expect(!prompt.contains("{{"))
  }

  @Test("LLM prompt renderer prepends source context when template omits context placeholder")
  func llmPromptRendererPrependsSourceContextWithoutPlaceholder() {
    let sourceContext = SelectionBarActionSourceContext(
      appName: "Safari",
      bundleID: "com.apple.Safari",
      sourceURL: "https://example.com",
      sourceKind: .webPage,
      excerpt: "Page content around selected text",
      isAvailable: true
    )

    let prompt = SelectionBarActionHandler.renderPrompt(
      template: "Summarize {{TEXT}}",
      text: "selected",
      sourceContext: sourceContext,
      includesSourceContext: true
    )

    #expect(prompt.hasPrefix("Source Context:"))
    #expect(prompt.contains("Page content around selected text"))
    #expect(prompt.hasSuffix("Summarize selected"))
  }

  @Test("LLM prompt renderer omits source context when action is not opted in")
  func llmPromptRendererOmitsSourceContextWhenDisabled() {
    let sourceContext = SelectionBarActionSourceContext(
      appName: "TextEdit",
      bundleID: "com.apple.TextEdit",
      sourceURL: "/tmp/note.txt",
      sourceKind: .textFile,
      excerpt: "secret source content",
      isAvailable: true
    )

    let prompt = SelectionBarActionHandler.renderPrompt(
      template: "{{TEXT}}\n{{CONTEXT}}\n{{SOURCE_URL}}\n{{APP_NAME}}\n{{BUNDLE_ID}}",
      text: "selected",
      sourceContext: sourceContext,
      includesSourceContext: false
    )

    #expect(prompt.contains("selected"))
    #expect(!prompt.contains("secret source content"))
    #expect(!prompt.contains("/tmp/note.txt"))
    #expect(!prompt.contains("TextEdit"))
    #expect(!prompt.contains("com.apple.TextEdit"))
    #expect(!prompt.contains("{{"))
  }

  @Test("LLM prompt renderer uses unavailable note when source context is missing")
  func llmPromptRendererUsesUnavailableSourceContextNote() {
    let prompt = SelectionBarActionHandler.renderPrompt(
      template: "Explain {{TEXT}} with context",
      text: "selected",
      sourceContext: nil,
      includesSourceContext: true
    )

    #expect(prompt.hasPrefix("Source Context:"))
    #expect(prompt.contains("Source context unavailable"))
    #expect(prompt.contains("Explain selected with context"))
  }

  @Test("LLM prompt renderer preserves placeholder-like text inside values")
  func llmPromptRendererPreservesPlaceholderLikeTextInsideValues() {
    let sourceContext = SelectionBarActionSourceContext(
      sourceURL: "/tmp/source.txt",
      sourceKind: .textFile,
      excerpt: "source excerpt",
      isAvailable: true
    )

    let prompt = SelectionBarActionHandler.renderPrompt(
      template: "Selected: {{TEXT}}",
      text: "literal {{CONTEXT}} token",
      sourceContext: sourceContext,
      includesSourceContext: true
    )

    #expect(prompt.contains("source excerpt"))
    #expect(prompt.contains("Selected: literal {{CONTEXT}} token"))
  }

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

  @Test("JavaScript-to-JavaScript pipeline transforms sequentially")
  func javaScriptPipelineTransformsSequentially() async throws {
    let handler = SelectionBarActionHandler()
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let trimAction = CustomActionConfig(
      id: UUID(),
      name: "Trim",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return input.trim(); }"
    )
    let wrapAction = CustomActionConfig(
      id: UUID(),
      name: "Wrap",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return '[' + input.toUpperCase() + ']'; }"
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: trimAction.id),
        CustomActionPipelineStep(actionID: wrapAction.id),
      ]
    )

    store.customActions = [trimAction, wrapAction, pipeline]

    let output = try await handler.process(text: "  hello  ", action: pipeline, settings: store)

    #expect(output == "[HELLO]")
  }

  @Test("JavaScript-to-LLM pipeline sends JavaScript output to the LLM prompt")
  func javaScriptToLLMPipelineUsesPreviousStepOutput() async throws {
    let capture = CompletionCapture()
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "openai-key" },
      dataLoader: { request in
        capture.record(request)
        let json = #"{"choices":[{"message":{"content":"final output"}}]}"#
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

    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Prepare",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: "function transform(input) { return input.trim().toUpperCase(); }"
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "Polish",
      prompt: "Polish {{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      outputMode: .inplace
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      outputMode: .resultWindow,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id),
        CustomActionPipelineStep(actionID: llmAction.id),
      ]
    )

    store.customActions = [jsAction, llmAction, pipeline]

    let output = try await handler.process(text: "  hello  ", action: pipeline, settings: store)

    #expect(output == "final output")
    #expect(capture.prompts == ["Polish HELLO"])
  }

  @Test("LLM source context is available to context-enabled pipeline steps")
  func pipelineLLMStepReceivesSourceContext() async throws {
    let capture = CompletionCapture()
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "openai-key" },
      dataLoader: { request in
        capture.record(request)
        let json = #"{"choices":[{"message":{"content":"explained"}}]}"#
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

    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Prepare",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return input.toUpperCase(); }"
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "Explain",
      prompt: "Text={{TEXT}}\nContext={{CONTEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      includesSourceContext: true
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id),
        CustomActionPipelineStep(actionID: llmAction.id),
      ]
    )
    let sourceContext = SelectionBarActionSourceContext(
      appName: "TextEdit",
      bundleID: "com.apple.TextEdit",
      sourceURL: "/tmp/source.txt",
      sourceKind: .textFile,
      excerpt: "Lines 9-10 of 10:\n9: context line\n10: selected",
      isAvailable: true
    )

    store.customActions = [jsAction, llmAction, pipeline]

    _ = try await handler.process(
      text: "selected",
      action: pipeline,
      settings: store,
      sourceContext: sourceContext
    )

    let prompt = try #require(capture.prompts.first)
    #expect(prompt.contains("Text=SELECTED"))
    #expect(prompt.contains("Source Context:"))
    #expect(prompt.contains("App: TextEdit"))
    #expect(prompt.contains("context line"))
  }

  @Test("pipeline ignores step output modes and returns final output")
  func pipelineIgnoresStepOutputModes() async throws {
    let handler = SelectionBarActionHandler()
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let inplaceStep = CustomActionConfig(
      id: UUID(),
      name: "Append A",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: "function transform(input) { return input + '-a'; }"
    )
    let resultWindowStep = CustomActionConfig(
      id: UUID(),
      name: "Append B",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: "function transform(input) { return input + '-b'; }"
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      outputMode: .inplace,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: inplaceStep.id),
        CustomActionPipelineStep(actionID: resultWindowStep.id),
      ]
    )

    store.customActions = [inplaceStep, resultWindowStep, pipeline]

    let output = try await handler.process(text: "input", action: pipeline, settings: store)

    #expect(output == "input-a-b")
  }

  @Test("pipeline fails fast when a step returns empty output")
  func pipelineFailsFastOnEmptyStepOutput() async {
    let capture = CompletionCapture()
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "openai-key" },
      dataLoader: { request in
        capture.record(request)
        let json = #"{"choices":[{"message":{"content":"should not run"}}]}"#
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

    let emptyAction = CustomActionConfig(
      id: UUID(),
      name: "Empty",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return '   '; }"
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "LLM",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: emptyAction.id),
        CustomActionPipelineStep(actionID: llmAction.id),
      ]
    )

    store.customActions = [emptyAction, llmAction, pipeline]

    do {
      _ = try await handler.process(text: "input", action: pipeline, settings: store)
      Issue.record("Expected emptyResult error")
    } catch let error as SelectionBarError {
      #expect(error == .emptyResult)
      #expect(capture.requestCount == 0)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("pipeline fails fast when a step throws")
  func pipelineFailsFastOnStepError() async {
    let capture = CompletionCapture()
    let client = SelectionBarOpenAIClient(
      apiKeyReader: { _ in "openai-key" },
      dataLoader: { request in
        capture.record(request)
        let json = #"{"choices":[{"message":{"content":"should not run"}}]}"#
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

    let brokenAction = CustomActionConfig(
      id: UUID(),
      name: "Broken",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "const noop = (input) => input;"
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "LLM",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: brokenAction.id),
        CustomActionPipelineStep(actionID: llmAction.id),
      ]
    )

    store.customActions = [brokenAction, llmAction, pipeline]

    do {
      _ = try await handler.process(text: "input", action: pipeline, settings: store)
      Issue.record("Expected javaScriptMissingTransform error")
    } catch let error as SelectionBarError {
      #expect(error == .javaScriptMissingTransform)
      #expect(capture.requestCount == 0)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
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

  @Test("JavaScript async transform processes through action handler")
  func javaScriptAsyncTransformProcessesThroughActionHandler() async throws {
    let handler = SelectionBarActionHandler()
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "Async JS",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: """
        async function transform(input) {
          return input.trim().toUpperCase();
        }
        """,
      isEnabled: false
    )

    let output = try await handler.process(text: "  hello async  ", action: action, settings: store)
    #expect(output == "HELLO ASYNC")
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
