import AppKit
import Foundation
import Observation

public enum CustomActionEnablementIssue: Sendable, Equatable {
  case missingProvider
  case missingModel
  case providerUnavailable
}

@MainActor
@Observable
public final class SelectionBarSettingsStore {
  private let defaults: UserDefaults
  private let storageKey: String
  private let keychain: any KeychainServiceProtocol
  @ObservationIgnored
  private var isReconcilingActions = false
  @ObservationIgnored
  private var persistenceSuppressionDepth = 0

  public static let defaultIgnoredApps: [IgnoredApp] = []
  public static let defaultClipboardFallbackIncludedAppCandidates: [IgnoredApp] = [
    IgnoredApp(id: "com.tencent.xinWeChat", name: "WeChat"),
    IgnoredApp(id: "ru.keepcoder.Telegram", name: "Telegram"),
  ]
  static var availableTerminalAppsResolver: @MainActor () -> [SelectionBarTerminalApp] = {
    SelectionBarTerminalCommandService().availableTerminalApps()
  }
  static var appInstallationResolver: @MainActor (String) -> Bool = { bundleID in
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }
  public static let defaultOpenAIModel = "gpt-4o-mini"
  public static let defaultOpenRouterModel = "openai/gpt-4o-mini"

  /// Callback triggered when selection bar enabled state changes.
  @ObservationIgnored
  public var onEnabledChanged: (() -> Void)?

  /// Callback triggered when ignored apps change.
  @ObservationIgnored
  public var onIgnoredAppsChanged: (() -> Void)?

  /// Callback triggered when clipboard-fallback included apps change.
  @ObservationIgnored
  public var onClipboardFallbackIncludedAppsChanged: (() -> Void)?

  /// Callback triggered when activation gating mode changes.
  @ObservationIgnored
  public var onActivationRequirementChanged: (() -> Void)?

  /// Cached API key availability for built-in providers.
  public private(set) var openAIAPIKeyConfigured: Bool
  public private(set) var openRouterAPIKeyConfigured: Bool
  public private(set) var deepLAPIKeyConfigured: Bool
  public private(set) var elevenLabsAPIKeyConfigured: Bool

  /// Cached API key availability for custom providers by ID.
  public private(set) var customProviderAPIKeyConfiguredByID: [UUID: Bool]

  public static var defaultClipboardFallbackIncludedApps: [IgnoredApp] {
    defaultClipboardFallbackIncludedAppCandidates.filter { candidate in
      appInstallationResolver(candidate.id)
    }
  }

  public var selectionBarEnabled: Bool {
    didSet {
      persistIfNeeded()
      onEnabledChanged?()
    }
  }

  /// When enabled, Selection Bar appears only while the activation modifier is held.
  public var selectionBarDoNotDisturbEnabled: Bool {
    didSet {
      persistIfNeeded()
      onActivationRequirementChanged?()
    }
  }

  /// Modifier key required when Do Not Disturb mode is enabled.
  public var selectionBarActivationModifier: SelectionBarActivationModifier {
    didSet {
      persistIfNeeded()
      onActivationRequirementChanged?()
    }
  }

  public var selectionBarLookupEnabled: Bool {
    didSet { persistIfNeeded() }
  }

  public var selectionBarLookupProvider: SelectionBarLookupProvider {
    didSet { persistIfNeeded() }
  }

  public var selectionBarLookupCustomScheme: String {
    didSet { persistIfNeeded() }
  }

  public var selectionBarSearchEngine: SelectionBarSearchEngine {
    didSet { persistIfNeeded() }
  }

  public var selectionBarSearchCustomScheme: String {
    didSet { persistIfNeeded() }
  }

  public var selectionBarTerminalApp: SelectionBarTerminalApp {
    didSet {
      ensureValidSelectionBarTerminalApp()
      persistIfNeeded()
    }
  }

  public var selectionBarSpeakEnabled: Bool {
    didSet { persistIfNeeded() }
  }

  /// Voice identifier for the Speak action. Empty means system default.
  public var selectionBarSpeakVoiceIdentifier: String {
    didSet { persistIfNeeded() }
  }

  /// Selected speak provider ID (e.g. "system-apple", "api-elevenlabs", or "custom-<uuid>").
  public var selectionBarSpeakProviderId: String {
    didSet { persistIfNeeded() }
  }

  /// Selected ElevenLabs voice ID.
  public var elevenLabsVoiceId: String {
    didSet { persistIfNeeded() }
  }

  /// Selected ElevenLabs model. Default: "eleven_v3".
  public var elevenLabsModelId: String {
    didSet { persistIfNeeded() }
  }

  /// Cached ElevenLabs voice list.
  public var availableElevenLabsVoices: [ElevenLabsVoice] {
    didSet { persistIfNeeded() }
  }

  public var selectionBarChatEnabled: Bool {
    didSet { persistIfNeeded() }
  }

  public var selectionBarChatProviderId: String {
    didSet { persistIfNeeded() }
  }

  public var selectionBarChatModelId: String {
    didSet { persistIfNeeded() }
  }

  public var selectionBarChatSessionLimit: Int {
    didSet { persistIfNeeded() }
  }

  public var selectionBarTranslationEnabled: Bool {
    didSet { persistIfNeeded() }
  }

  public var selectionBarTranslationProviderId: String {
    didSet {
      ensureValidSelectionBarTranslationProvider()
      persistIfNeeded()
    }
  }

  public var selectionBarIgnoredApps: [IgnoredApp] {
    didSet {
      persistIfNeeded()
      onIgnoredAppsChanged?()
    }
  }

  public var selectionBarClipboardFallbackIncludedApps: [IgnoredApp] {
    didSet {
      persistIfNeeded()
      onClipboardFallbackIncludedAppsChanged?()
    }
  }

  /// OpenAI chat model.
  public var openAIModel: String {
    didSet { persistIfNeeded() }
  }

  /// OpenAI translation model. Empty means use `openAIModel`.
  public var openAITranslationModel: String {
    didSet { persistIfNeeded() }
  }

  /// Cached OpenAI model list.
  public var availableOpenAIModels: [String] {
    didSet { persistIfNeeded() }
  }

  /// OpenRouter chat model.
  public var openRouterModel: String {
    didSet { persistIfNeeded() }
  }

  /// OpenRouter translation model. Empty means use `openRouterModel`.
  public var openRouterTranslationModel: String {
    didSet { persistIfNeeded() }
  }

  /// Cached OpenRouter model list.
  public var availableOpenRouterModels: [String] {
    didSet { persistIfNeeded() }
  }

  /// Target language for Selection Bar translation-capable providers.
  public var selectionBarTranslationTargetLanguage: String {
    didSet {
      ensureValidSelectionBarTranslationTargetLanguage()
      persistIfNeeded()
    }
  }

  /// Custom OpenAI-compatible providers.
  public var customLLMProviders: [CustomLLMProvider] {
    didSet {
      if reconcileActionsAvailabilityIfNeeded(checkProviderAvailability: false) {
        return
      }
      persistIfNeeded()
    }
  }

  /// Per-device app language override via AppleLanguages.
  /// Empty string means "System Default" (no override).
  public var appLanguage: String {
    didSet {
      if appLanguage.isEmpty {
        if defaults === UserDefaults.standard {
          UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        defaults.removeObject(forKey: "SelectionBar_AppLanguageOverride")
      } else {
        if defaults === UserDefaults.standard {
          UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
        }
        defaults.set(appLanguage, forKey: "SelectionBar_AppLanguageOverride")
      }
    }
  }

  /// Configurable text actions.
  public var customActions: [CustomActionConfig] {
    didSet {
      if isReconcilingActions {
        persistIfNeeded()
        return
      }
      if reconcileActionsAvailabilityIfNeeded(checkProviderAvailability: false) {
        return
      }
      persistIfNeeded()
    }
  }

  /// Built-in key-binding actions shown in the Built-in tab.
  public var builtInKeyBindingActions: [CustomActionConfig] {
    didSet {
      if isReconcilingActions {
        persistIfNeeded()
        return
      }
      if reconcileActionsAvailabilityIfNeeded(checkProviderAvailability: false) {
        return
      }
      persistIfNeeded()
    }
  }

  public init(
    defaults: UserDefaults = .standard,
    storageKey: String = "SelectionBar.settings",
    keychain: any KeychainServiceProtocol = KeychainHelper.shared
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.keychain = keychain

    selectionBarEnabled = false
    selectionBarDoNotDisturbEnabled = false
    selectionBarActivationModifier = .option
    selectionBarLookupEnabled = true
    selectionBarLookupProvider = .systemDictionary
    selectionBarLookupCustomScheme = ""
    selectionBarSearchEngine = .google
    selectionBarSearchCustomScheme = ""
    selectionBarTerminalApp = .terminal
    selectionBarSpeakEnabled = true
    selectionBarSpeakVoiceIdentifier = ""
    selectionBarSpeakProviderId = SelectionBarSpeakSystemProvider.apple.rawValue
    elevenLabsVoiceId = ""
    elevenLabsModelId = "eleven_v3"
    availableElevenLabsVoices = []
    selectionBarChatEnabled = false
    selectionBarChatProviderId = ""
    selectionBarChatModelId = ""
    selectionBarChatSessionLimit = 50
    selectionBarTranslationEnabled = true
    selectionBarTranslationProviderId = SelectionBarTranslationAppProvider.bob.rawValue
    selectionBarIgnoredApps = Self.defaultIgnoredApps
    selectionBarClipboardFallbackIncludedApps = Self.defaultClipboardFallbackIncludedApps
    openAIModel = Self.defaultOpenAIModel
    openAITranslationModel = ""
    availableOpenAIModels = []
    openRouterModel = Self.defaultOpenRouterModel
    openRouterTranslationModel = ""
    availableOpenRouterModels = []
    selectionBarTranslationTargetLanguage = TranslationLanguageCatalog.defaultTargetLanguage
    customLLMProviders = []
    customActions = []
    builtInKeyBindingActions = []
    appLanguage = defaults.string(forKey: "SelectionBar_AppLanguageOverride") ?? ""
    openAIAPIKeyConfigured = false
    openRouterAPIKeyConfigured = false
    deepLAPIKeyConfigured = false
    elevenLabsAPIKeyConfigured = false
    customProviderAPIKeyConfiguredByID = [:]

    load()
    refreshCredentialAvailability()
    ensureValidSelectionBarTranslationProvider()
    ensureValidSelectionBarTranslationTargetLanguage()
    ensureValidSelectionBarTerminalApp()
    ensureValidSelectionBarSpeakProvider()
    ensureValidChatProvider()
    _ = reconcileActionsAvailabilityIfNeeded(checkProviderAvailability: false)
  }

  /// Enabled actions in toolbar order: key bindings first, then custom LLM/JS actions.
  public var orderedEnabledSelectionBarActions: [CustomActionConfig] {
    let keyBindings = builtInKeyBindingActions.filter(\.isEnabled)
    let custom = customActions.filter { $0.isEnabled && $0.kind != .keyBinding }
    return keyBindings + custom
  }

  public func availableSelectionBarTranslationProviders() -> [SelectionBarTranslationProviderOption]
  {
    var providers = SelectionBarTranslationAppProvider.allCases.map { provider in
      SelectionBarTranslationProviderOption(
        id: provider.rawValue,
        name: provider.displayName,
        kind: .app
      )
    }

    if !availableOpenAIModels.isEmpty || openAIAPIKeyConfigured {
      providers.append(
        SelectionBarTranslationProviderOption(
          id: "openai",
          name: "OpenAI",
          kind: .llm
        ))
    }
    if !availableOpenRouterModels.isEmpty || openRouterAPIKeyConfigured {
      providers.append(
        SelectionBarTranslationProviderOption(
          id: "openrouter",
          name: "OpenRouter",
          kind: .llm
        ))
    }
    if deepLAPIKeyConfigured {
      providers.append(
        SelectionBarTranslationProviderOption(
          id: "deepl",
          name: "DeepL",
          kind: .llm
        ))
    }

    for provider in customLLMProviders where provider.capabilities.contains(.translation) {
      guard isCustomProviderAPIKeyConfigured(id: provider.id) else { continue }
      providers.append(
        SelectionBarTranslationProviderOption(
          id: provider.providerId,
          name: provider.name,
          kind: .llm
        ))
    }

    return providers
  }

  public func availableChatProviders() -> [SelectionBarTranslationProviderOption] {
    var providers: [SelectionBarTranslationProviderOption] = []

    if openAIAPIKeyConfigured {
      providers.append(
        SelectionBarTranslationProviderOption(id: "openai", name: "OpenAI", kind: .llm))
    }
    if openRouterAPIKeyConfigured {
      providers.append(
        SelectionBarTranslationProviderOption(id: "openrouter", name: "OpenRouter", kind: .llm))
    }

    for provider in customLLMProviders where provider.capabilities.contains(.llm) {
      guard isCustomProviderAPIKeyConfigured(id: provider.id) else { continue }
      providers.append(
        SelectionBarTranslationProviderOption(
          id: provider.providerId, name: provider.name, kind: .llm))
    }

    return providers
  }

  public func isSelectionBarLLMTranslationProvider(id: String) -> Bool {
    availableSelectionBarTranslationProviders().contains { provider in
      provider.id == id && provider.kind == .llm
    }
  }

  public func ensureValidSelectionBarTranslationProvider() {
    let available = availableSelectionBarTranslationProviders()
    guard !available.isEmpty else { return }

    if available.contains(where: { $0.id == selectionBarTranslationProviderId }) {
      return
    }

    if let llmFallback = available.first(where: { $0.kind == .llm })?.id {
      selectionBarTranslationProviderId = llmFallback
    } else if let fallback = available.first?.id {
      selectionBarTranslationProviderId = fallback
    }
  }

  public func availableSelectionBarTerminalApps() -> [SelectionBarTerminalApp] {
    Self.availableTerminalAppsResolver()
  }

  public func ensureValidSelectionBarTerminalApp() {
    let available = availableSelectionBarTerminalApps()
    guard !available.isEmpty else { return }

    if available.contains(selectionBarTerminalApp) {
      return
    }

    if available.contains(.terminal) {
      selectionBarTerminalApp = .terminal
    } else if let fallback = available.first {
      selectionBarTerminalApp = fallback
    }
  }

  public func availableSelectionBarSpeakProviders() -> [SelectionBarSpeakProviderOption] {
    var providers = SelectionBarSpeakSystemProvider.allCases.map { provider in
      SelectionBarSpeakProviderOption(
        id: provider.rawValue,
        name: provider.displayName,
        kind: .system
      )
    }

    if elevenLabsAPIKeyConfigured {
      providers.append(
        SelectionBarSpeakProviderOption(
          id: SelectionBarSpeakAPIProvider.elevenLabs.rawValue,
          name: SelectionBarSpeakAPIProvider.elevenLabs.displayName,
          kind: .api
        ))
    }

    for provider in customLLMProviders where provider.capabilities.contains(.tts) {
      guard isCustomProviderAPIKeyConfigured(id: provider.id) else { continue }
      providers.append(
        SelectionBarSpeakProviderOption(
          id: provider.providerId,
          name: provider.name,
          kind: .custom
        ))
    }

    return providers
  }

  public func isSelectionBarSystemSpeakProvider(id: String) -> Bool {
    SelectionBarSpeakSystemProvider(rawValue: id) != nil
  }

  public func ensureValidSelectionBarSpeakProvider() {
    let available = availableSelectionBarSpeakProviders()
    guard !available.isEmpty else { return }

    if available.contains(where: { $0.id == selectionBarSpeakProviderId }) {
      return
    }

    if let systemFallback = available.first(where: { $0.kind == .system })?.id {
      selectionBarSpeakProviderId = systemFallback
    } else if let fallback = available.first?.id {
      selectionBarSpeakProviderId = fallback
    }
  }

  public func ensureValidSelectionBarTranslationTargetLanguage() {
    if TranslationLanguageCatalog.contains(code: selectionBarTranslationTargetLanguage) {
      return
    }
    selectionBarTranslationTargetLanguage = TranslationLanguageCatalog.defaultTargetLanguage
  }

  public func ensureValidChatProvider() {
    let available = availableChatProviders()
    guard !available.isEmpty else { return }

    if available.contains(where: { $0.id == selectionBarChatProviderId }) {
      return
    }

    if let fallback = available.first?.id {
      selectionBarChatProviderId = fallback
    }
  }

  /// Refresh cached API key availability from Keychain.
  public func refreshCredentialAvailability() {
    openAIAPIKeyConfigured = isAPIKeyConfiguredInKeychain("openai_api_key")
    openRouterAPIKeyConfigured = isAPIKeyConfiguredInKeychain("openrouter_api_key")
    deepLAPIKeyConfigured = isAPIKeyConfiguredInKeychain("deepl_api_key")
    elevenLabsAPIKeyConfigured = isAPIKeyConfiguredInKeychain("elevenlabs_api_key")

    var customAvailability: [UUID: Bool] = [:]
    for provider in customLLMProviders {
      customAvailability[provider.id] = isAPIKeyConfiguredInKeychain(provider.keychainKey)
    }
    customProviderAPIKeyConfiguredByID = customAvailability
  }

  public func isCustomProviderAPIKeyConfigured(id: UUID) -> Bool {
    customProviderAPIKeyConfiguredByID[id] ?? false
  }

  /// Add a custom provider and persist its API key in Keychain.
  public func addCustomLLMProvider(_ provider: CustomLLMProvider, apiKey: String) {
    withPersistenceSuppressed {
      customLLMProviders.append(provider)
      let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedKey.isEmpty {
        _ = keychain.save(key: provider.keychainKey, value: trimmedKey)
      }
      refreshCredentialAvailability()
      ensureValidSelectionBarTranslationProvider()
      ensureValidSelectionBarSpeakProvider()
      ensureValidChatProvider()
      _ = reconcileActionsAvailabilityIfNeeded()
    }
    persistIfNeeded()
  }

  /// Update an existing custom provider. When `apiKey` is provided, update Keychain too.
  public func updateCustomLLMProvider(_ provider: CustomLLMProvider, apiKey: String? = nil) {
    guard let index = customLLMProviders.firstIndex(where: { $0.id == provider.id }) else {
      return
    }
    withPersistenceSuppressed {
      customLLMProviders[index] = provider
      if let apiKey {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
          _ = keychain.delete(key: provider.keychainKey)
        } else {
          _ = keychain.save(key: provider.keychainKey, value: trimmedKey)
        }
      }
      refreshCredentialAvailability()
      ensureValidSelectionBarTranslationProvider()
      ensureValidSelectionBarSpeakProvider()
      ensureValidChatProvider()
      _ = reconcileActionsAvailabilityIfNeeded()
    }
    persistIfNeeded()
  }

  /// Remove a custom provider and delete its API key from Keychain.
  public func removeCustomLLMProvider(id: UUID) {
    guard let provider = customLLMProviders.first(where: { $0.id == id }) else { return }
    withPersistenceSuppressed {
      _ = keychain.delete(key: provider.keychainKey)
      customLLMProviders.removeAll { $0.id == id }
      refreshCredentialAvailability()
      ensureValidSelectionBarTranslationProvider()
      ensureValidSelectionBarSpeakProvider()
      ensureValidChatProvider()
      _ = reconcileActionsAvailabilityIfNeeded()
    }
    persistIfNeeded()
  }

  /// Call this after built-in provider keys are saved/cleared from UI.
  public func handleCredentialChange() {
    withPersistenceSuppressed {
      refreshCredentialAvailability()
      ensureValidSelectionBarTranslationProvider()
      ensureValidSelectionBarSpeakProvider()
      ensureValidChatProvider()
      _ = reconcileActionsAvailabilityIfNeeded()
    }
    persistIfNeeded()
  }

  public func customLLMProvider(id: UUID) -> CustomLLMProvider? {
    customLLMProviders.first { $0.id == id }
  }

  public func canEnableCustomAction(_ action: CustomActionConfig) -> Bool {
    switch action.kind {
    case .javascript:
      return true
    case .llm:
      return llmActionEnablementIssue(action) == nil
    case .keyBinding:
      return isValidKeyBindingAction(action)
    }
  }

  public func llmActionEnablementIssue(_ action: CustomActionConfig) -> CustomActionEnablementIssue?
  {
    guard action.kind == .llm else { return nil }

    let provider = action.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !provider.isEmpty else { return .missingProvider }

    let model = action.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else { return .missingModel }

    guard isAvailableLLMProvider(providerID: provider) else { return .providerUnavailable }
    return nil
  }

  /// Reconcile all configurable actions:
  /// - custom actions: migrate legacy JS icons and disable invalid enabled LLM actions
  /// - built-in key bindings: disable invalid enabled shortcuts
  ///
  /// - Parameter checkProviderAvailability: When `true`, enabled LLM actions
  ///   whose provider API key is missing will be disabled. Pass `false` on
  ///   startup / load to avoid false negatives caused by Keychain being
  ///   inaccessible after ad-hoc re-signing. Structural issues (missing
  ///   provider/model, invalid shortcuts) are always checked regardless of this flag.
  @discardableResult
  public func reconcileActionsAvailabilityIfNeeded(
    checkProviderAvailability: Bool = true
  ) -> Bool {
    let cleanEscapesTemplate = CustomActionConfig.createJavaScriptCleanEscapesTemplate()
    let reconciledCustomActions = customActions.map { action in
      var updated = migrateLegacyCleanEscapesIconIfNeeded(
        action,
        cleanEscapesTemplate: cleanEscapesTemplate
      )
      guard updated.isEnabled else { return updated }

      switch updated.kind {
      case .javascript:
        return updated
      case .keyBinding:
        if !isValidKeyBindingAction(updated) {
          updated.isEnabled = false
        }
        return updated
      case .llm:
        if let issue = llmActionEnablementIssue(updated) {
          // Always disable for structural issues (missing provider / model).
          // Only disable for provider-unavailable when explicitly requested,
          // because Keychain may be inaccessible after ad-hoc re-signing.
          let isStructuralIssue = issue != .providerUnavailable
          if isStructuralIssue || checkProviderAvailability {
            updated.isEnabled = false
          }
        }
        return updated
      }
    }

    let reconciledBuiltInKeyBindingActions = builtInKeyBindingActions.map { action in
      var updated = action

      if updated.kind != .keyBinding {
        updated.kind = .keyBinding
        updated.outputMode = .resultWindow
        updated.modelProvider = ""
        updated.modelId = ""
        updated.script = CustomActionConfig.defaultJavaScriptTemplate
      }

      if updated.isEnabled && !isValidKeyBindingAction(updated) {
        updated.isEnabled = false
      }

      return updated
    }

    guard
      reconciledCustomActions != customActions
        || reconciledBuiltInKeyBindingActions != builtInKeyBindingActions
    else { return false }

    isReconcilingActions = true
    withPersistenceSuppressed {
      customActions = reconciledCustomActions
      builtInKeyBindingActions = reconciledBuiltInKeyBindingActions
    }
    isReconcilingActions = false
    persistIfNeeded()
    return true
  }

  private func isAvailableLLMProvider(providerID: String) -> Bool {
    switch providerID {
    case "openai":
      return openAIAPIKeyConfigured
    case "openrouter":
      return openRouterAPIKeyConfigured
    default:
      guard
        let provider = customLLMProviders.first(where: {
          $0.providerId == providerID && $0.capabilities.contains(.llm)
        })
      else {
        return false
      }
      return isCustomProviderAPIKeyConfigured(id: provider.id)
    }
  }

  private func isAPIKeyConfiguredInKeychain(_ key: String) -> Bool {
    let value = keychain.readString(key: key) ?? ""
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func isValidKeyBindingAction(_ action: CustomActionConfig) -> Bool {
    guard SelectionBarKeyboardShortcutParser.parse(action.keyBinding) != nil else { return false }
    for override in action.keyBindingOverrides {
      let bundleID = override.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
      let keyBinding = override.keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !bundleID.isEmpty, SelectionBarKeyboardShortcutParser.parse(keyBinding) != nil else {
        return false
      }
    }
    return true
  }

  private func migrateLegacyCleanEscapesIconIfNeeded(
    _ action: CustomActionConfig,
    cleanEscapesTemplate: CustomActionConfig
  ) -> CustomActionConfig {
    guard action.kind == .javascript else { return action }

    let legacyIcons: Set<String> = ["wand.and.stars", "eraser"]
    guard let iconValue = action.icon?.value, legacyIcons.contains(iconValue) else { return action }

    let matchesBuiltInTemplate = action.templateId == cleanEscapesTemplate.templateId
    let matchesStarterTemplate =
      action.templateId == nil
      && action.name == cleanEscapesTemplate.name
      && action.script == cleanEscapesTemplate.script
    guard matchesBuiltInTemplate || matchesStarterTemplate else { return action }

    guard let preferredIcon = cleanEscapesTemplate.icon else { return action }
    var updated = action
    updated.icon = preferredIcon
    return updated
  }

  private func save() {
    let data = StoredSettings(
      selectionBarEnabled: selectionBarEnabled,
      selectionBarDoNotDisturbEnabled: selectionBarDoNotDisturbEnabled,
      selectionBarActivationModifier: selectionBarActivationModifier.rawValue,
      selectionBarLookupEnabled: selectionBarLookupEnabled,
      selectionBarLookupProvider: selectionBarLookupProvider.rawValue,
      selectionBarLookupCustomScheme: selectionBarLookupCustomScheme,
      selectionBarSearchEngine: selectionBarSearchEngine.rawValue,
      selectionBarSearchCustomScheme: selectionBarSearchCustomScheme,
      selectionBarTerminalApp: selectionBarTerminalApp.rawValue,
      selectionBarSpeakEnabled: selectionBarSpeakEnabled,
      selectionBarSpeakVoiceIdentifier: selectionBarSpeakVoiceIdentifier,
      selectionBarSpeakProviderId: selectionBarSpeakProviderId,
      elevenLabsVoiceId: elevenLabsVoiceId,
      elevenLabsModelId: elevenLabsModelId,
      availableElevenLabsVoices: availableElevenLabsVoices,
      selectionBarChatEnabled: selectionBarChatEnabled,
      selectionBarChatProviderId: selectionBarChatProviderId,
      selectionBarChatModelId: selectionBarChatModelId,
      selectionBarChatSessionLimit: selectionBarChatSessionLimit,
      selectionBarTranslationEnabled: selectionBarTranslationEnabled,
      selectionBarTranslationProviderId: selectionBarTranslationProviderId,
      selectionBarIgnoredApps: selectionBarIgnoredApps,
      selectionBarClipboardFallbackIncludedApps: selectionBarClipboardFallbackIncludedApps,
      openAIModel: openAIModel,
      openAITranslationModel: openAITranslationModel,
      availableOpenAIModels: availableOpenAIModels,
      openRouterModel: openRouterModel,
      openRouterTranslationModel: openRouterTranslationModel,
      availableOpenRouterModels: availableOpenRouterModels,
      selectionBarTranslationTargetLanguage: selectionBarTranslationTargetLanguage,
      customLLMProviders: customLLMProviders,
      customActions: customActions,
      builtInKeyBindingActions: builtInKeyBindingActions
    )

    if let encoded = try? JSONEncoder().encode(data) {
      defaults.set(encoded, forKey: storageKey)
    }
  }

  private func load() {
    guard
      let data = defaults.data(forKey: storageKey),
      let settings = try? JSONDecoder().decode(StoredSettings.self, from: data)
    else {
      return
    }

    withPersistenceSuppressed {
      selectionBarEnabled = settings.selectionBarEnabled ?? false
      selectionBarDoNotDisturbEnabled = settings.selectionBarDoNotDisturbEnabled ?? false
      selectionBarActivationModifier =
        SelectionBarActivationModifier(rawValue: settings.selectionBarActivationModifier ?? "")
        ?? .option
      selectionBarLookupEnabled = settings.selectionBarLookupEnabled ?? true
      selectionBarLookupProvider =
        SelectionBarLookupProvider(rawValue: settings.selectionBarLookupProvider ?? "")
        ?? .systemDictionary
      selectionBarLookupCustomScheme = settings.selectionBarLookupCustomScheme ?? ""
      selectionBarSearchEngine =
        SelectionBarSearchEngine(rawValue: settings.selectionBarSearchEngine ?? "")
        ?? .google
      selectionBarSearchCustomScheme = settings.selectionBarSearchCustomScheme ?? ""
      selectionBarTerminalApp =
        SelectionBarTerminalApp(rawValue: settings.selectionBarTerminalApp ?? "") ?? .terminal
      selectionBarSpeakEnabled = settings.selectionBarSpeakEnabled ?? true
      selectionBarSpeakVoiceIdentifier = settings.selectionBarSpeakVoiceIdentifier ?? ""
      selectionBarSpeakProviderId =
        settings.selectionBarSpeakProviderId
        ?? SelectionBarSpeakSystemProvider.apple.rawValue
      elevenLabsVoiceId = settings.elevenLabsVoiceId ?? ""
      elevenLabsModelId = settings.elevenLabsModelId ?? "eleven_v3"
      availableElevenLabsVoices = settings.availableElevenLabsVoices ?? []
      selectionBarChatEnabled = settings.selectionBarChatEnabled ?? false
      selectionBarChatProviderId = settings.selectionBarChatProviderId ?? ""
      selectionBarChatModelId = settings.selectionBarChatModelId ?? ""
      selectionBarChatSessionLimit = settings.selectionBarChatSessionLimit ?? 50
      selectionBarTranslationEnabled = settings.selectionBarTranslationEnabled ?? true
      selectionBarTranslationProviderId =
        settings.selectionBarTranslationProviderId
        ?? SelectionBarTranslationAppProvider.bob.rawValue
      selectionBarIgnoredApps = settings.selectionBarIgnoredApps ?? Self.defaultIgnoredApps
      selectionBarClipboardFallbackIncludedApps =
        settings.selectionBarClipboardFallbackIncludedApps
        ?? Self.defaultClipboardFallbackIncludedApps
      openAIModel = settings.openAIModel ?? Self.defaultOpenAIModel
      openAITranslationModel = settings.openAITranslationModel ?? ""
      availableOpenAIModels = settings.availableOpenAIModels ?? []
      openRouterModel = settings.openRouterModel ?? Self.defaultOpenRouterModel
      openRouterTranslationModel = settings.openRouterTranslationModel ?? ""
      availableOpenRouterModels = settings.availableOpenRouterModels ?? []
      selectionBarTranslationTargetLanguage =
        settings.selectionBarTranslationTargetLanguage
        ?? TranslationLanguageCatalog.defaultTargetLanguage
      customLLMProviders = settings.customLLMProviders ?? []
      customActions = (settings.customActions ?? []).filter { $0.kind != .keyBinding }
      builtInKeyBindingActions =
        (settings.builtInKeyBindingActions ?? []).filter { $0.kind == .keyBinding }
    }
  }

  private func withPersistenceSuppressed(_ operation: () -> Void) {
    persistenceSuppressionDepth += 1
    defer { persistenceSuppressionDepth = max(0, persistenceSuppressionDepth - 1) }
    operation()
  }

  private func persistIfNeeded() {
    guard persistenceSuppressionDepth == 0 else { return }
    save()
  }
}

private struct StoredSettings: Codable {
  let selectionBarEnabled: Bool?
  let selectionBarDoNotDisturbEnabled: Bool?
  let selectionBarActivationModifier: String?
  let selectionBarLookupEnabled: Bool?
  let selectionBarLookupProvider: String?
  let selectionBarLookupCustomScheme: String?
  let selectionBarSearchEngine: String?
  let selectionBarSearchCustomScheme: String?
  let selectionBarTerminalApp: String?
  let selectionBarSpeakEnabled: Bool?
  let selectionBarSpeakVoiceIdentifier: String?
  let selectionBarSpeakProviderId: String?
  let elevenLabsVoiceId: String?
  let elevenLabsModelId: String?
  let availableElevenLabsVoices: [ElevenLabsVoice]?
  let selectionBarChatEnabled: Bool?
  let selectionBarChatProviderId: String?
  let selectionBarChatModelId: String?
  let selectionBarChatSessionLimit: Int?
  let selectionBarTranslationEnabled: Bool?
  let selectionBarTranslationProviderId: String?
  let selectionBarIgnoredApps: [IgnoredApp]?
  let selectionBarClipboardFallbackIncludedApps: [IgnoredApp]?
  let openAIModel: String?
  let openAITranslationModel: String?
  let availableOpenAIModels: [String]?
  let openRouterModel: String?
  let openRouterTranslationModel: String?
  let availableOpenRouterModels: [String]?
  let selectionBarTranslationTargetLanguage: String?
  let customLLMProviders: [CustomLLMProvider]?
  let customActions: [CustomActionConfig]?
  let builtInKeyBindingActions: [CustomActionConfig]?
}
