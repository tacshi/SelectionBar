import Foundation
import Testing

@testable import SelectionBarCore

/// Guards the settings persistence table: every persisted property is set to a
/// non-default value, written out, and read back by a fresh store over the same
/// UserDefaults suite. A property that is missing from the persistence table
/// fails here instead of silently losing the user's setting.
@Suite("SelectionBarSettingsStore Round Trip")
@MainActor
struct SettingsStoreRoundTripTests {
  @Test("every persisted property survives a save/reload cycle")
  func everyPersistedPropertyRoundTrips() {
    let originalTerminalResolver = SelectionBarSettingsStore.availableTerminalAppsResolver
    SelectionBarSettingsStore.availableTerminalAppsResolver = { [.terminal, .ghostty, .warp] }
    defer { SelectionBarSettingsStore.availableTerminalAppsResolver = originalTerminalResolver }

    let suite = "SelectionBarCoreTests.RoundTrip.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let keychain = InMemoryKeychain()
    _ = keychain.save(key: "openai_api_key", value: "openai-key")
    _ = keychain.save(key: "openrouter_api_key", value: "openrouter-key")
    _ = keychain.save(key: "elevenlabs_api_key", value: "elevenlabs-key")

    let store = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    let customProvider = CustomLLMProvider(
      id: UUID(),
      name: "Round Trip Provider",
      baseURL: URL(string: "https://roundtrip.example.com/v1")!,
      models: ["rt-model"],
      capabilities: [.llm, .translation],
      llmModel: "rt-model",
      translationModel: "rt-model-translate"
    )
    let jsAction = CustomActionConfig(
      id: UUID(),
      name: "Round Trip JS",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      script: "function transform(input) { return input.trim(); }",
      isEnabled: true,
      icon: CustomActionIcon(value: "text.badge.checkmark")
    )
    let llmAction = CustomActionConfig(
      id: UUID(),
      name: "Round Trip LLM",
      prompt: "{{TEXT}}",
      modelProvider: "openai",
      modelId: "gpt-custom",
      kind: .llm,
      isEnabled: true
    )
    let keyBindingAction = CustomActionConfig(
      id: UUID(),
      name: "Round Trip Shortcut",
      prompt: "",
      modelProvider: "",
      modelId: "",
      kind: .keyBinding,
      keyBinding: "cmd+shift+r",
      isEnabled: true,
      isBuiltIn: true,
      icon: CustomActionIcon(value: "bold")
    )
    let profile = SelectionBarActionProfile(
      id: UUID(),
      app: IgnoredApp(id: "com.example.RoundTrip", name: "Round Trip"),
      isEnabled: true,
      actionIDs: [keyBindingAction.id, jsAction.id]
    )
    let ignoredApps = [IgnoredApp(id: "com.example.Ignored", name: "Ignored")]
    let clipboardApps = [IgnoredApp(id: "com.example.Clipboard", name: "Clipboard")]
    let voices = [ElevenLabsVoice(voiceId: "voice-123", name: "Round Trip Voice")]

    store.selectionBarEnabled = true
    store.selectionBarDoNotDisturbEnabled = true
    store.selectionBarActivationModifier = .shift
    store.selectionBarLookupEnabled = false
    store.selectionBarLookupProvider = .customApp
    store.selectionBarLookupCustomScheme = "lookup-scheme"
    store.selectionBarSearchEngine = .duckDuckGo
    store.selectionBarSearchCustomScheme = "search-scheme"
    store.selectionBarTerminalApp = .ghostty
    store.selectionBarSpeakEnabled = false
    store.selectionBarSpeakVoiceIdentifier = "com.apple.voice.roundtrip"
    store.selectionBarSpeakProviderId = SelectionBarSpeakAPIProvider.elevenLabs.rawValue
    store.elevenLabsVoiceId = "voice-123"
    store.elevenLabsModelId = "eleven_multilingual_v2"
    store.availableElevenLabsVoices = voices
    store.selectionBarChatEnabled = true
    store.selectionBarChatProviderId = "openrouter"
    store.selectionBarChatModelId = "chat-model"
    store.selectionBarChatSessionLimit = 7
    store.selectionBarTranslationEnabled = false
    store.selectionBarTranslationProviderId = SelectionBarTranslationAppProvider.eudic.rawValue
    store.selectionBarIgnoredApps = ignoredApps
    store.selectionBarClipboardFallbackIncludedApps = clipboardApps
    store.openAIModel = "gpt-custom"
    store.openAITranslationModel = "gpt-custom-translate"
    store.availableOpenAIModels = ["gpt-custom", "gpt-other"]
    store.openRouterModel = "vendor/model"
    store.openRouterTranslationModel = "vendor/model-translate"
    store.availableOpenRouterModels = ["vendor/model", "vendor/other"]
    store.selectionBarTranslationTargetLanguage = "ja"
    store.customLLMProviders = [customProvider]
    store.customActions = [jsAction, llmAction]
    store.builtInKeyBindingActions = [keyBindingAction]
    store.actionProfiles = [profile]
    store.appLanguage = "ja"

    // Sanity: nothing above was rejected or rewritten by the store itself,
    // so a mismatch after reload can only come from persistence.
    #expect(store.selectionBarTerminalApp == .ghostty)
    #expect(store.selectionBarSpeakProviderId == SelectionBarSpeakAPIProvider.elevenLabs.rawValue)
    #expect(store.customActions == [jsAction, llmAction])
    #expect(store.builtInKeyBindingActions == [keyBindingAction])

    // Persistence is coalesced, so force the pending write out before reading
    // it back through a second store.
    store.flushPendingWrites()

    let reloaded = SelectionBarSettingsStore(
      defaults: defaults,
      storageKey: "test.settings",
      keychain: keychain
    )

    #expect(reloaded.selectionBarEnabled == true)
    #expect(reloaded.selectionBarDoNotDisturbEnabled == true)
    #expect(reloaded.selectionBarActivationModifier == .shift)
    #expect(reloaded.selectionBarLookupEnabled == false)
    #expect(reloaded.selectionBarLookupProvider == .customApp)
    #expect(reloaded.selectionBarLookupCustomScheme == "lookup-scheme")
    #expect(reloaded.selectionBarSearchEngine == .duckDuckGo)
    #expect(reloaded.selectionBarSearchCustomScheme == "search-scheme")
    #expect(reloaded.selectionBarTerminalApp == .ghostty)
    #expect(reloaded.selectionBarSpeakEnabled == false)
    #expect(reloaded.selectionBarSpeakVoiceIdentifier == "com.apple.voice.roundtrip")
    #expect(
      reloaded.selectionBarSpeakProviderId == SelectionBarSpeakAPIProvider.elevenLabs.rawValue)
    #expect(reloaded.elevenLabsVoiceId == "voice-123")
    #expect(reloaded.elevenLabsModelId == "eleven_multilingual_v2")
    #expect(reloaded.availableElevenLabsVoices == voices)
    #expect(reloaded.selectionBarChatEnabled == true)
    #expect(reloaded.selectionBarChatProviderId == "openrouter")
    #expect(reloaded.selectionBarChatModelId == "chat-model")
    #expect(reloaded.selectionBarChatSessionLimit == 7)
    #expect(reloaded.selectionBarTranslationEnabled == false)
    #expect(
      reloaded.selectionBarTranslationProviderId
        == SelectionBarTranslationAppProvider.eudic.rawValue)
    #expect(reloaded.selectionBarIgnoredApps == ignoredApps)
    #expect(reloaded.selectionBarClipboardFallbackIncludedApps == clipboardApps)
    #expect(reloaded.openAIModel == "gpt-custom")
    #expect(reloaded.openAITranslationModel == "gpt-custom-translate")
    #expect(reloaded.availableOpenAIModels == ["gpt-custom", "gpt-other"])
    #expect(reloaded.openRouterModel == "vendor/model")
    #expect(reloaded.openRouterTranslationModel == "vendor/model-translate")
    #expect(reloaded.availableOpenRouterModels == ["vendor/model", "vendor/other"])
    #expect(reloaded.selectionBarTranslationTargetLanguage == "ja")
    #expect(reloaded.customLLMProviders == [customProvider])
    #expect(reloaded.customActions == [jsAction, llmAction])
    #expect(reloaded.builtInKeyBindingActions == [keyBindingAction])
    #expect(reloaded.actionProfiles == [profile])
    #expect(reloaded.appLanguage == "ja")
  }

  @Test("every persisted property differs from the value a fresh store starts with")
  func roundTripValuesAreAllNonDefault() {
    let originalTerminalResolver = SelectionBarSettingsStore.availableTerminalAppsResolver
    SelectionBarSettingsStore.availableTerminalAppsResolver = { [.terminal, .ghostty, .warp] }
    defer { SelectionBarSettingsStore.availableTerminalAppsResolver = originalTerminalResolver }

    let pristine = makeStore(keychain: InMemoryKeychain())

    #expect(pristine.selectionBarEnabled != true)
    #expect(pristine.selectionBarDoNotDisturbEnabled != true)
    #expect(pristine.selectionBarActivationModifier != .shift)
    #expect(pristine.selectionBarLookupEnabled != false)
    #expect(pristine.selectionBarLookupProvider != .customApp)
    #expect(pristine.selectionBarLookupCustomScheme != "lookup-scheme")
    #expect(pristine.selectionBarSearchEngine != .duckDuckGo)
    #expect(pristine.selectionBarSearchCustomScheme != "search-scheme")
    #expect(pristine.selectionBarTerminalApp != .ghostty)
    #expect(pristine.selectionBarSpeakEnabled != false)
    #expect(pristine.selectionBarSpeakVoiceIdentifier != "com.apple.voice.roundtrip")
    #expect(
      pristine.selectionBarSpeakProviderId != SelectionBarSpeakAPIProvider.elevenLabs.rawValue)
    #expect(pristine.elevenLabsVoiceId != "voice-123")
    #expect(pristine.elevenLabsModelId != "eleven_multilingual_v2")
    #expect(pristine.availableElevenLabsVoices.isEmpty)
    #expect(pristine.selectionBarChatEnabled != true)
    #expect(pristine.selectionBarChatProviderId != "openrouter")
    #expect(pristine.selectionBarChatModelId != "chat-model")
    #expect(pristine.selectionBarChatSessionLimit != 7)
    #expect(pristine.selectionBarTranslationEnabled != false)
    #expect(
      pristine.selectionBarTranslationProviderId
        != SelectionBarTranslationAppProvider.eudic.rawValue)
    #expect(pristine.selectionBarIgnoredApps.map(\.id) != ["com.example.Ignored"])
    #expect(
      pristine.selectionBarClipboardFallbackIncludedApps.map(\.id) != ["com.example.Clipboard"])
    #expect(pristine.openAIModel != "gpt-custom")
    #expect(pristine.openAITranslationModel != "gpt-custom-translate")
    #expect(pristine.availableOpenAIModels.isEmpty)
    #expect(pristine.openRouterModel != "vendor/model")
    #expect(pristine.openRouterTranslationModel != "vendor/model-translate")
    #expect(pristine.availableOpenRouterModels.isEmpty)
    #expect(pristine.selectionBarTranslationTargetLanguage != "ja")
    #expect(pristine.customLLMProviders.isEmpty)
    #expect(pristine.customActions.isEmpty)
    #expect(pristine.builtInKeyBindingActions.isEmpty)
    #expect(pristine.actionProfiles.isEmpty)
    #expect(pristine.appLanguage != "ja")
  }
}
