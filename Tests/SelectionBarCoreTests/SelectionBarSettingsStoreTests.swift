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

  @Test("legacy settings payload without built-in key bindings preserves existing values")
  func legacyPayloadWithoutBuiltInKeyBindingsPreservesSettings() {
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

    #expect(store.selectionBarEnabled == true)
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
    let pipelineAction = CustomActionConfig(
      id: UUID(),
      name: "JS Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      isEnabled: true,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id)
      ]
    )

    store.builtInKeyBindingActions = [keyBindingAction]
    store.customActions = [llmAction, jsAction, strayCustomKeyBinding, pipelineAction]

    let ordered = store.orderedEnabledSelectionBarActions
    #expect(
      ordered.map(\.id) == [keyBindingAction.id, llmAction.id, jsAction.id, pipelineAction.id])
  }

  @Test("pipeline with disabled JavaScript and LLM steps can be enabled")
  func pipelineCanUseDisabledJavaScriptAndLLMSteps() {
    let keychain = InMemoryKeychain()
    _ = keychain.save(key: "openai_api_key", value: "openai-key")
    let store = makeStore(keychain: keychain)

    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Trim",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return input.trim(); }",
      isEnabled: false
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "Polish",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      isEnabled: false
    )
    var pipeline = CustomActionConfig(
      id: UUID(),
      name: "Prepare",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      isEnabled: false,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id),
        CustomActionPipelineStep(actionID: llmAction.id),
      ]
    )

    store.customActions = [jsAction, llmAction, pipeline]

    #expect(store.customActionEnablementIssue(pipeline) == nil)
    #expect(store.canEnableCustomAction(pipeline))

    pipeline.isEnabled = true
    store.customActions = [jsAction, llmAction, pipeline]

    #expect(store.customActions.first(where: { $0.id == pipeline.id })?.isEnabled == true)
  }

  @Test("invalid pipeline steps prevent enabling")
  func invalidPipelineStepsPreventEnabling() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let emptyPipeline = CustomActionConfig(
      name: "Empty",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline
    )
    #expect(store.customActionEnablementIssue(emptyPipeline) == .emptyPipeline)
    #expect(!store.canEnableCustomAction(emptyPipeline))

    let missingPipeline = CustomActionConfig(
      name: "Missing",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [CustomActionPipelineStep(actionID: UUID())]
    )
    #expect(store.customActionEnablementIssue(missingPipeline) == .missingPipelineStep)

    let keyBindingAction = CustomActionConfig(
      id: UUID(),
      name: "Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+b"
    )
    let pipelineStepAction = CustomActionConfig(
      id: UUID(),
      name: "Nested Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [CustomActionPipelineStep(actionID: keyBindingAction.id)]
    )
    let invalidLLMAction = CustomActionConfig(
      id: UUID(),
      name: "Broken LLM",
      prompt: "{{TEXT}}",
      modelProvider: "",
      modelId: "",
      kind: .llm
    )
    store.customActions = [keyBindingAction, pipelineStepAction, invalidLLMAction]

    let keyBindingPipeline = CustomActionConfig(
      name: "Uses Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [CustomActionPipelineStep(actionID: keyBindingAction.id)]
    )
    #expect(store.customActionEnablementIssue(keyBindingPipeline) == .invalidPipelineStep)

    let nestedPipeline = CustomActionConfig(
      name: "Uses Pipeline",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [CustomActionPipelineStep(actionID: pipelineStepAction.id)]
    )
    #expect(store.customActionEnablementIssue(nestedPipeline) == .invalidPipelineStep)

    let invalidLLMPipeline = CustomActionConfig(
      name: "Uses Broken LLM",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [CustomActionPipelineStep(actionID: invalidLLMAction.id)]
    )
    #expect(store.customActionEnablementIssue(invalidLLMPipeline) == .invalidPipelineStep)
  }

  @Test("reconcile disables enabled pipeline when references disappear or become invalid")
  func reconcileDisablesEnabledPipelineWhenReferencesBreak() {
    let keychain = InMemoryKeychain()
    _ = keychain.save(key: "openai_api_key", value: "openai-key")
    let store = makeStore(keychain: keychain)

    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Trim",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return input.trim(); }",
      isEnabled: false
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "Polish",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      isEnabled: false
    )
    let pipeline = CustomActionConfig(
      id: UUID(),
      name: "Prepare",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      isEnabled: true,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id),
        CustomActionPipelineStep(actionID: llmAction.id),
      ]
    )

    store.customActions = [jsAction, llmAction, pipeline]
    #expect(store.customActions.first(where: { $0.id == pipeline.id })?.isEnabled == true)

    store.customActions = [llmAction, pipeline]

    let missingReferencePipeline = store.customActions.first { $0.id == pipeline.id }
    #expect(missingReferencePipeline?.isEnabled == false)
    #expect(missingReferencePipeline?.pipelineSteps.count == 2)

    var brokenLLMAction = llmAction
    brokenLLMAction.modelId = ""
    var enabledPipeline = pipeline
    enabledPipeline.pipelineSteps = [CustomActionPipelineStep(actionID: brokenLLMAction.id)]
    enabledPipeline.isEnabled = true

    store.customActions = [brokenLLMAction, enabledPipeline]

    #expect(store.customActions.first(where: { $0.id == pipeline.id })?.isEnabled == false)
  }

  @Test("pipeline source-context detection follows referenced LLM steps")
  func pipelineSourceContextDetectionFollowsReferencedLLMSteps() {
    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Trim",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript
    )
    let llmWithoutContext = CustomActionConfig(
      id: UUID(),
      name: "Polish",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      includesSourceContext: false
    )
    let llmWithContext = CustomActionConfig(
      id: UUID(),
      name: "Explain",
      prompt: "{{TEXT}}\n{{CONTEXT}}",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      kind: .llm,
      includesSourceContext: true
    )
    let plainPipeline = CustomActionConfig(
      id: UUID(),
      name: "Plain",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id),
        CustomActionPipelineStep(actionID: llmWithoutContext.id),
      ]
    )
    let contextPipeline = CustomActionConfig(
      id: UUID(),
      name: "Context",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .pipeline,
      pipelineSteps: [
        CustomActionPipelineStep(actionID: jsAction.id),
        CustomActionPipelineStep(actionID: llmWithContext.id),
      ]
    )

    store.customActions = [
      jsAction, llmWithoutContext, llmWithContext, plainPipeline, contextPipeline,
    ]

    #expect(!store.actionNeedsSourceContext(plainPipeline))
    #expect(store.actionNeedsSourceContext(contextPipeline))
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

  @Test("clipboard fallback included apps default and persist")
  func clipboardFallbackIncludedAppsDefaultAndPersist() {
    let originalResolver = SelectionBarSettingsStore.appInstallationResolver
    SelectionBarSettingsStore.appInstallationResolver = { bundleID in
      bundleID == "com.tencent.xinWeChat"
    }
    defer {
      SelectionBarSettingsStore.appInstallationResolver = originalResolver
    }

    let suite = "SelectionBarCoreTests.ClipboardFallbackApps.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    #expect(
      Set(store.selectionBarClipboardFallbackIncludedApps.map(\.id))
        == ["com.tencent.xinWeChat"]
    )

    var callbackCount = 0
    store.onClipboardFallbackIncludedAppsChanged = {
      callbackCount += 1
    }

    store.selectionBarClipboardFallbackIncludedApps.append(
      IgnoredApp(id: "com.example.ChatApp", name: "ChatApp")
    )

    #expect(callbackCount == 1)

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    #expect(
      Set(reloaded.selectionBarClipboardFallbackIncludedApps.map(\.id))
        == ["com.tencent.xinWeChat", "com.example.ChatApp"]
    )
  }

  @Test("terminal app selection persists across reload")
  func terminalAppSelectionPersistsAcrossReload() {
    let originalResolver = SelectionBarSettingsStore.availableTerminalAppsResolver
    SelectionBarSettingsStore.availableTerminalAppsResolver = {
      [.terminal, .ghostty, .warp]
    }
    defer {
      SelectionBarSettingsStore.availableTerminalAppsResolver = originalResolver
    }

    let suite = "SelectionBarCoreTests.Terminals.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    store.selectionBarTerminalApp = .ghostty

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    #expect(reloaded.selectionBarTerminalApp == .ghostty)
  }

  @Test("terminal app falls back to terminal when stored choice disappears")
  func terminalAppFallsBackWhenStoredChoiceDisappears() {
    let originalResolver = SelectionBarSettingsStore.availableTerminalAppsResolver
    SelectionBarSettingsStore.availableTerminalAppsResolver = {
      [.terminal, .ghostty]
    }
    defer {
      SelectionBarSettingsStore.availableTerminalAppsResolver = originalResolver
    }

    let suite = "SelectionBarCoreTests.TerminalFallback.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    store.selectionBarTerminalApp = .ghostty

    SelectionBarSettingsStore.availableTerminalAppsResolver = {
      [.terminal, .warp]
    }

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )
    #expect(reloaded.selectionBarTerminalApp == .terminal)
  }

  @Test("available terminal apps are ordered and filtered by resolver")
  func availableTerminalAppsUseResolverOrder() {
    let originalResolver = SelectionBarSettingsStore.availableTerminalAppsResolver
    SelectionBarSettingsStore.availableTerminalAppsResolver = {
      [.warp, .ghostty, .terminal]
    }
    defer {
      SelectionBarSettingsStore.availableTerminalAppsResolver = originalResolver
    }

    let keychain = InMemoryKeychain()
    let store = makeStore(keychain: keychain)

    #expect(store.availableSelectionBarTerminalApps() == [.warp, .ghostty, .terminal])
  }

}
