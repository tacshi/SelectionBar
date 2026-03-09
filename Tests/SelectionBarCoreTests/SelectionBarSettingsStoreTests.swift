import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarSettingsStore Tests")
@MainActor
struct SelectionBarSettingsStoreTests {
  @Test("custom provider add/update/remove updates keychain and cached availability")
  func customProviderLifecycleUpdatesCredentialCache() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    var provider = CustomLLMProvider(
      id: UUID(),
      name: "DeepSeek",
      baseURL: URL(string: "https://api.deepseek.com/v1")!,
      capabilities: [.llm, .translation],
      llmModel: "deepseek-chat"
    )

    store.addCustomLLMProvider(provider, apiKey: "  secret-key  ")

    #expect(keychain.values[provider.keychainKey] == "secret-key")
    #expect(store.isCustomProviderAPIKeyConfigured(id: provider.id))

    store.updateCustomLLMProvider(provider, apiKey: "")

    #expect(keychain.values[provider.keychainKey] == nil)
    #expect(!store.isCustomProviderAPIKeyConfigured(id: provider.id))
    #expect(keychain.deleteCalls.contains(provider.keychainKey))

    provider.name = "DeepSeek Updated"
    store.updateCustomLLMProvider(provider, apiKey: "another-key")

    #expect(keychain.values[provider.keychainKey] == "another-key")
    #expect(store.customLLMProvider(id: provider.id)?.name == "DeepSeek Updated")
    #expect(store.isCustomProviderAPIKeyConfigured(id: provider.id))

    store.removeCustomLLMProvider(id: provider.id)

    #expect(store.customLLMProvider(id: provider.id) == nil)
    #expect(!store.isCustomProviderAPIKeyConfigured(id: provider.id))
    #expect(keychain.deleteCalls.last == provider.keychainKey)
  }

  @Test(
    "translation providers include only configured providers and fallback when selection disappears"
  )
  func translationProvidersAndFallbackBehavior() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let translationProvider = CustomLLMProvider(
      id: UUID(),
      name: "TranslateOnly",
      baseURL: URL(string: "https://translate.example.com/v1")!,
      capabilities: [.translation],
      llmModel: "",
      translationModel: "model-translate"
    )

    let llmOnlyProvider = CustomLLMProvider(
      id: UUID(),
      name: "LLMOnly",
      baseURL: URL(string: "https://llm.example.com/v1")!,
      capabilities: [.llm],
      llmModel: "model-chat"
    )

    store.addCustomLLMProvider(translationProvider, apiKey: "")
    store.addCustomLLMProvider(llmOnlyProvider, apiKey: "llm-key")

    var providerIDs = Set(store.availableSelectionBarTranslationProviders().map(\.id))
    #expect(!providerIDs.contains(translationProvider.providerId))
    #expect(!providerIDs.contains(llmOnlyProvider.providerId))

    store.updateCustomLLMProvider(translationProvider, apiKey: "translate-key")

    providerIDs = Set(store.availableSelectionBarTranslationProviders().map(\.id))
    #expect(providerIDs.contains(translationProvider.providerId))

    store.selectionBarTranslationProviderId = translationProvider.providerId
    store.removeCustomLLMProvider(id: translationProvider.id)

    providerIDs = Set(store.availableSelectionBarTranslationProviders().map(\.id))
    #expect(!providerIDs.contains(translationProvider.providerId))
    #expect(providerIDs.contains(store.selectionBarTranslationProviderId))
  }

  @Test("enabled custom-provider LLM action is disabled when provider becomes unavailable")
  func reconcileDisablesEnabledActionWhenProviderLosesKey() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let provider = CustomLLMProvider(
      id: UUID(),
      name: "CustomOpenAI",
      baseURL: URL(string: "https://custom.example.com/v1")!,
      capabilities: [.llm],
      llmModel: "model-chat"
    )

    store.addCustomLLMProvider(provider, apiKey: "provider-key")

    let action = CustomActionConfig(
      name: "Use Custom",
      prompt: "Translate: {{TEXT}}",
      modelProvider: provider.providerId,
      modelId: "model-chat",
      kind: .llm,
      isEnabled: true
    )

    store.customActions = [action]
    #expect(store.customActions[0].isEnabled)
    #expect(store.llmActionEnablementIssue(store.customActions[0]) == nil)

    store.updateCustomLLMProvider(provider, apiKey: "")

    #expect(store.llmActionEnablementIssue(store.customActions[0]) == .providerUnavailable)
    #expect(store.customActions[0].isEnabled == false)
  }

  @Test("enabled built-in key-binding action is disabled when shortcut is invalid")
  func reconcileDisablesEnabledBuiltInKeyBindingActionWhenShortcutIsInvalid() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "Broken Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+",
      isEnabled: true
    )

    store.builtInKeyBindingActions = [action]

    #expect(store.builtInKeyBindingActions.count == 1)
    #expect(store.builtInKeyBindingActions[0].isEnabled == false)
  }

  @Test("enabled built-in key-binding action is disabled when app override shortcut is invalid")
  func reconcileDisablesEnabledBuiltInKeyBindingWhenOverrideShortcutIsInvalid() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let action = CustomActionConfig(
      name: "Bold Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+b",
      keyBindingOverrides: [
        CustomActionKeyBindingOverride(
          bundleID: "com.microsoft.Word",
          appName: "Microsoft Word",
          keyBinding: "cmd+"
        )
      ],
      isEnabled: true
    )

    store.builtInKeyBindingActions = [action]

    #expect(store.builtInKeyBindingActions.count == 1)
    #expect(store.builtInKeyBindingActions[0].isEnabled == false)
  }

  @Test("settings payload missing built-in key bindings is ignored")
  func legacyPayloadWithoutBuiltInKeyBindingsIsIgnored() {
    let suite = "SelectionBarCoreTests.StrictSettings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let legacyJSON = """
      {
        "selectionBarEnabled": true,
        "customActions": []
      }
      """
    defaults.set(Data(legacyJSON.utf8), forKey: "test.settings")

    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: InMemoryKeychain()
    )

    #expect(store.selectionBarEnabled == false)
    #expect(store.customActions.isEmpty)
    #expect(store.builtInKeyBindingActions.isEmpty)
  }

  @Test("built-in key bindings persist across reload")
  func builtInKeyBindingsPersistAcrossReload() {
    let suite = "SelectionBarCoreTests.BuiltInKeys.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    let action = CustomActionConfig(
      id: UUID(),
      name: "Italic Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      outputMode: .resultWindow,
      script: CustomActionConfig.defaultJavaScriptTemplate,
      keyBinding: "cmd+i",
      keyBindingOverrides: [
        CustomActionKeyBindingOverride(
          bundleID: "com.microsoft.Word",
          appName: "Microsoft Word",
          keyBinding: "cmd+shift+i"
        )
      ],
      isEnabled: true,
      isBuiltIn: true,
      templateId: nil,
      icon: CustomActionIcon(value: "italic")
    )
    store.builtInKeyBindingActions = [action]

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    #expect(reloaded.builtInKeyBindingActions == [action])
  }

  @Test("ordered enabled actions prioritize built-in key bindings")
  func orderedEnabledActionsPrioritizeBuiltInKeyBindings() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let keyBindingAction = CustomActionConfig(
      id: UUID(),
      name: "Bold Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+b",
      isEnabled: true
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "Summarize",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      isEnabled: true
    )
    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Title Case",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return input; }",
      isEnabled: true
    )
    let strayCustomKeyBinding = CustomActionConfig(
      id: UUID(),
      name: "Legacy Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+u",
      isEnabled: true
    )

    store.builtInKeyBindingActions = [keyBindingAction]
    store.customActions = [llmAction, jsAction, strayCustomKeyBinding]

    let ordered = store.orderedEnabledSelectionBarActions
    #expect(ordered.map(\.id) == [keyBindingAction.id, llmAction.id, jsAction.id])
  }

  @Test("custom web search engine and custom scheme persist across reload")
  func customWebSearchSettingsPersist() {
    let suite = "SelectionBarCoreTests.Search.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    store.selectionBarSearchEngine = .custom
    store.selectionBarSearchCustomScheme = "myapp"

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    #expect(reloaded.selectionBarSearchEngine == .custom)
    #expect(reloaded.selectionBarSearchCustomScheme == "myapp")
  }

  @Test("do-not-disturb activation settings default, notify, and persist")
  func doNotDisturbActivationSettingsLifecycle() {
    let suite = "SelectionBarCoreTests.DND.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    #expect(store.selectionBarDoNotDisturbEnabled == false)
    #expect(store.selectionBarActivationModifier == .option)

    var callbackCount = 0
    store.onActivationRequirementChanged = {
      callbackCount += 1
    }

    store.selectionBarDoNotDisturbEnabled = true
    store.selectionBarActivationModifier = .shift

    #expect(callbackCount == 2)

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    #expect(reloaded.selectionBarDoNotDisturbEnabled == true)
    #expect(reloaded.selectionBarActivationModifier == .shift)
  }
}
