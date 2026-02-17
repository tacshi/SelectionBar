import Foundation
import SelectionBarCore
import Testing

@Suite("SelectionBarCore Tests")
@MainActor
struct SelectionBarCoreTests {
  @Test("searchURL encodes query and uses correct endpoints")
  func searchURLQueryAndEndpoints() {
    let query = "C++ url 编码"
    let cases: [(SelectionBarSearchEngine, String, String, String)] = [
      (.google, "www.google.com", "/search", "q"),
      (.baidu, "www.baidu.com", "/s", "wd"),
      (.bing, "www.bing.com", "/search", "q"),
      (.sogou, "www.sogou.com", "/web", "query"),
      (.so360, "www.so.com", "/s", "q"),
      (.yandex, "yandex.com", "/search/", "text"),
      (.duckDuckGo, "duckduckgo.com", "/", "q"),
    ]

    for (engine, host, path, queryName) in cases {
      let url = engine.searchURL(for: query)
      #expect(url != nil)

      let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
      #expect(components?.host == host)
      #expect(components?.path == path)
      #expect(components?.queryItems?.first(where: { $0.name == queryName })?.value == query)
    }
  }

  @Test("custom search URL template replaces {{query}} with encoded text")
  func customSearchURLTemplate() {
    let query = "hello world"
    let candidates = SelectionBarSearchEngine.custom.searchURLCandidates(
      for: query,
      customConfiguration: "https://example.com/search?q={{query}}"
    )

    #expect(candidates.count == 1)
    #expect(candidates.first?.absoluteString == "https://example.com/search?q=hello%20world")
  }

  @Test("custom search scheme generates ordered fallback candidates")
  func customSearchSchemeCandidates() {
    let query = "hello world"
    let candidates = SelectionBarSearchEngine.custom.searchURLCandidates(
      for: query,
      customConfiguration: "myapp"
    )
    let urls = candidates.map(\.absoluteString)
    #expect(
      urls
        == [
          "myapp://search?query=hello%20world",
          "myapp://search?q=hello%20world",
          "myapp://lookup?word=hello%20world",
          "myapp://dict?word=hello%20world",
          "myapp://hello%20world",
        ]
    )
  }

  @Test("custom search configuration validation handles valid and invalid inputs")
  func customSearchConfigurationValidation() {
    #expect(!SelectionBarSearchEngine.custom.isConfigurationValid(customConfiguration: ""))
    #expect(
      !SelectionBarSearchEngine.custom.isConfigurationValid(customConfiguration: "bad scheme"))
    #expect(SelectionBarSearchEngine.custom.isConfigurationValid(customConfiguration: "myapp"))
    #expect(
      SelectionBarSearchEngine.custom.isConfigurationValid(
        customConfiguration: "https://example.com/search?q={{query}}")
    )
    #expect(
      !SelectionBarSearchEngine.custom.isConfigurationValid(
        customConfiguration: "example.com/search?q={{query}}")
    )

    #expect(
      SelectionBarSearchEngine.google.isConfigurationValid(customConfiguration: "")
    )
  }

  @Test("urlToOpen accepts explicit http and https URLs")
  func urlToOpenExplicitSchemes() {
    let action = SelectionBarActionHandler()

    #expect(action.urlToOpen(text: "https://example.com/path?x=1") != nil)
    #expect(action.urlToOpen(text: "http://example.com") != nil)
  }

  @Test("urlToOpen infers https for bare domains and localhost")
  func urlToOpenInferredScheme() {
    let action = SelectionBarActionHandler()

    #expect(action.urlToOpen(text: "example.com")?.absoluteString == "https://example.com")
    #expect(
      action.urlToOpen(text: "localhost:3000")?.absoluteString == "https://localhost:3000")
  }

  @Test("urlToOpen rejects invalid URL-like inputs")
  func urlToOpenRejectsInvalidInputs() {
    let action = SelectionBarActionHandler()

    #expect(action.urlToOpen(text: "not-a-url") == nil)
    #expect(action.urlToOpen(text: "hello world.com") == nil)
    #expect(action.urlToOpen(text: "ftp://example.com") == nil)
  }

  @Test("translation app providers expose expected URL candidates")
  func translationProviderURLCandidates() {
    let encoded = "hello"

    let eudicCandidates = SelectionBarTranslationAppProvider.eudic.translationURLCandidates(
      encodedQuery: encoded)
    #expect(eudicCandidates == ["eudic://dict/hello"])

    let bobCandidates = SelectionBarTranslationAppProvider.bob.translationURLCandidates(
      encodedQuery: encoded)
    #expect(bobCandidates.isEmpty)
  }

  @Test("legacy custom action decoding defaults to JavaScript kind and result window mode")
  func customActionLegacyDecodeDefaults() throws {
    let actionID = UUID()
    let json = """
      {
        "id": "\(actionID.uuidString)",
        "name": "Legacy Action",
        "prompt": "Process: {{TEXT}}",
        "modelProvider": "openai",
        "modelId": "gpt-4o-mini",
        "isEnabled": true,
        "isBuiltIn": false
      }
      """

    let decoded = try JSONDecoder().decode(CustomActionConfig.self, from: Data(json.utf8))
    #expect(decoded.id == actionID)
    #expect(decoded.kind == .javascript)
    #expect(decoded.outputMode == .resultWindow)
    #expect(decoded.script == CustomActionConfig.defaultJavaScriptTemplate)
  }

  @Test("javascript custom action roundtrips through Codable")
  func customActionJavaScriptRoundTrip() throws {
    let original = CustomActionConfig(
      id: UUID(),
      name: "JS Transform",
      prompt: "Unused",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: "function transform(input) { return input.toUpperCase(); }",
      isEnabled: true,
      isBuiltIn: false,
      templateId: nil,
      icon: CustomActionIcon(value: "bolt")
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CustomActionConfig.self, from: encoded)
    #expect(decoded == original)
  }

  @Test("javascript runner returns transformed text")
  func javaScriptRunnerReturnsOutput() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let script = """
      function transform(input) {
        return input.trim().toUpperCase();
      }
      """

    let output = try await runner.run(script: script, input: "  hello ")
    #expect(output == "HELLO")
  }

  @Test("javascript format JSON template formats valid JSON and keeps invalid input")
  func javaScriptFormatJSONTemplate() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let template = CustomActionConfig.createJavaScriptFormatJSONTemplate()

    let formatted = try await runner.run(
      script: template.script,
      input: "{\"a\":1,\"b\":{\"c\":2}}"
    )
    #expect(
      formatted
        == "{\n  \"a\": 1,\n  \"b\": {\n    \"c\": 2\n  }\n}"
    )

    let invalid = try await runner.run(
      script: template.script,
      input: "{ not-json }"
    )
    #expect(invalid == "{ not-json }")
  }

  @Test("javascript starter templates replace line utilities with URL and JWT tools")
  func javaScriptStarterTemplateList() {
    let names = Set(CustomActionConfig.createJavaScriptStarterTemplates().map(\.name))
    #expect(names.contains("URL Toolkit"))
    #expect(names.contains("JWT Decode"))
    #expect(!names.contains("Bulletize Lines"))
    #expect(!names.contains("Remove Empty Lines"))
  }

  @Test("javascript URL toolkit template parses URL components and query params")
  func javaScriptURLToolkitTemplate() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let template = CustomActionConfig.createJavaScriptURLToolkitTemplate()

    #expect(template.outputMode == .resultWindow)
    #expect(template.icon?.value == "link")

    let output = try await runner.run(
      script: template.script,
      input: "https://example.com/path/to?q=hello%20world&lang=en#frag"
    )

    #expect(output.contains("Host: example.com"))
    #expect(output.contains("Path: /path/to"))
    #expect(output.contains("Fragment: frag"))
    #expect(output.contains("1. q = hello world"))
    #expect(output.contains("2. lang = en"))
  }

  @Test("javascript JWT decode template decodes header and payload")
  func javaScriptJWTDecodeTemplate() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let template = CustomActionConfig.createJavaScriptJWTDecodeTemplate()

    #expect(template.outputMode == .resultWindow)
    #expect(template.icon?.value == "key.horizontal")

    let token =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
      + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ."
      + "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    let output = try await runner.run(script: template.script, input: token)

    #expect(output.contains("Header:"))
    #expect(output.contains("\"typ\": \"JWT\""))
    #expect(output.contains("Payload:"))
    #expect(output.contains("\"name\": \"John Doe\""))
    #expect(output.contains("Numeric date fields:"))
    #expect(output.contains("iat: 1516239022 ("))
  }

  @Test("javascript timestamp converter template handles epoch and ISO inputs")
  func javaScriptTimestampConverterTemplate() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let template = CustomActionConfig.createJavaScriptTimestampConverterTemplate()

    #expect(template.outputMode == .resultWindow)
    #expect(template.icon?.value == "clock.arrow.circlepath")

    let fromEpoch = try await runner.run(
      script: template.script,
      input: "1704067200"
    )
    #expect(fromEpoch.contains("Detected as: Unix timestamp (seconds)"))
    #expect(fromEpoch.contains("UTC ISO 8601: 2024-01-01T00:00:00.000Z"))
    #expect(fromEpoch.contains("Epoch milliseconds: 1704067200000"))
    #expect(fromEpoch.contains("Epoch nanoseconds: 1704067200000000000"))

    let fromISO = try await runner.run(
      script: template.script,
      input: "2024-01-01T00:00:00Z"
    )
    #expect(fromISO.contains("Detected as: Date/time string"))
    #expect(fromISO.contains("Epoch seconds: 1704067200"))
    #expect(fromISO.contains("RFC 2822 (UTC): Mon, 01 Jan 2024 00:00:00 GMT"))
  }

  @Test("javascript timestamp converter template preserves microsecond precision")
  func javaScriptTimestampConverterMicrosecondPrecision() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let template = CustomActionConfig.createJavaScriptTimestampConverterTemplate()

    let output = try await runner.run(
      script: template.script,
      input: "1770842929843842"
    )

    #expect(output.contains("Detected as: Unix timestamp (microseconds)"))
    #expect(output.contains("Epoch seconds: 1770842929.843842"))
    #expect(output.contains("Epoch milliseconds: 1770842929843.842"))
    #expect(output.contains("Epoch microseconds: 1770842929843842"))
    #expect(output.contains("Epoch nanoseconds: 1770842929843842000"))
  }

  @Test("javascript clean escapes template decodes escaped text")
  func javaScriptCleanEscapesTemplate() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let template = CustomActionConfig.createJavaScriptCleanEscapesTemplate()
    #expect(template.icon?.value == "eraser.xmark")

    let escapedObject = "{\\\"a\\\":1,\\\"b\\\":\\\"x\\\"}"
    let cleanedObject = try await runner.run(
      script: template.script,
      input: escapedObject
    )
    #expect(cleanedObject == "{\"a\":1,\"b\":\"x\"}")

    let escapedUnicode = "hello, \\\\u4f60\\\\u597d"
    let cleanedUnicode = try await runner.run(
      script: template.script,
      input: escapedUnicode
    )
    #expect(cleanedUnicode == "hello, 你好")
  }

  @Test("javascript runner fails when transform function is missing")
  func javaScriptRunnerMissingTransform() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let script = "const notTransform = (input) => input;"

    do {
      _ = try await runner.run(script: script, input: "hello")
      Issue.record("Expected missing transform error.")
    } catch let error as SelectionBarJavaScriptRunnerError {
      #expect(error == .missingTransform)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("javascript runner fails when return type is not string")
  func javaScriptRunnerInvalidReturnType() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let script = """
      function transform(input) {
        return 42;
      }
      """

    do {
      _ = try await runner.run(script: script, input: "hello")
      Issue.record("Expected invalid return type error.")
    } catch let error as SelectionBarJavaScriptRunnerError {
      #expect(error == .invalidReturnType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("javascript runner returns timeout error for long-running script")
  func javaScriptRunnerTimeout() async throws {
    let runner = SelectionBarJavaScriptRunner(defaultTimeout: .milliseconds(800))
    let script = """
      function transform(input) {
        const start = Date.now();
        while (Date.now() - start < 200) {}
        return input;
      }
      """

    do {
      _ = try await runner.run(script: script, input: "hello", timeout: .milliseconds(10))
      Issue.record("Expected timeout error.")
    } catch let error as SelectionBarJavaScriptRunnerError {
      #expect(error == .timeout)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("cannot enable LLM action without provider and model")
  func llmActionRequiresProviderAndModel() {
    let defaultsSuite = "SelectionBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: defaultsSuite)!
    defer { defaults.removePersistentDomain(forName: defaultsSuite) }

    let store = SelectionBarSettingsStore(
      defaults: defaults, storageKey: "test.settings", keychain: InMemoryKeychain())

    let missingProvider = CustomActionConfig(
      name: "Missing Provider",
      prompt: "x",
      modelProvider: "",
      modelId: "gpt-4o-mini",
      kind: .llm,
      isEnabled: false
    )
    #expect(store.llmActionEnablementIssue(missingProvider) == .missingProvider)
    #expect(store.canEnableCustomAction(missingProvider) == false)

    let missingModel = CustomActionConfig(
      name: "Missing Model",
      prompt: "x",
      modelProvider: "openai",
      modelId: "",
      kind: .llm,
      isEnabled: false
    )
    #expect(store.llmActionEnablementIssue(missingModel) == .missingModel)
    #expect(store.canEnableCustomAction(missingModel) == false)
  }

  @Test("reconcile disables invalid enabled LLM action")
  func reconcileDisablesInvalidEnabledLLMAction() {
    let defaultsSuite = "SelectionBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: defaultsSuite)!
    defer { defaults.removePersistentDomain(forName: defaultsSuite) }

    let store = SelectionBarSettingsStore(
      defaults: defaults, storageKey: "test.settings", keychain: InMemoryKeychain())
    let invalidEnabledAction = CustomActionConfig(
      name: "Broken LLM Action",
      prompt: "x",
      modelProvider: "",
      modelId: "",
      kind: .llm,
      isEnabled: true
    )

    store.customActions = [invalidEnabledAction]

    #expect(store.customActions.count == 1)
    #expect(store.customActions[0].isEnabled == false)
  }

  @Test("reconcile migrates legacy clean escapes icon")
  func reconcileMigratesLegacyCleanEscapesIcon() {
    let defaultsSuite = "SelectionBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: defaultsSuite)!
    defer { defaults.removePersistentDomain(forName: defaultsSuite) }

    let store = SelectionBarSettingsStore(
      defaults: defaults, storageKey: "test.settings", keychain: InMemoryKeychain())
    let template = CustomActionConfig.createJavaScriptCleanEscapesTemplate()
    let legacyAction = CustomActionConfig(
      name: template.name,
      prompt: CustomActionConfig.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: template.script,
      isEnabled: false,
      isBuiltIn: false,
      templateId: nil,
      icon: CustomActionIcon(value: "wand.and.stars")
    )
    let untouchedAction = CustomActionConfig(
      name: "Unrelated",
      prompt: CustomActionConfig.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: CustomActionConfig.defaultJavaScriptTemplate,
      isEnabled: false,
      isBuiltIn: false,
      templateId: nil,
      icon: CustomActionIcon(value: "wand.and.stars")
    )

    store.customActions = [legacyAction, untouchedAction]

    #expect(store.customActions[0].icon?.value == "eraser.xmark")
    #expect(store.customActions[1].icon?.value == "wand.and.stars")
  }

}
