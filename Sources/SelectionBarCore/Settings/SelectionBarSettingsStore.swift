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
  private var isReconcilingCustomActions = false
  @ObservationIgnored
  private var persistenceSuppressionDepth = 0

  public static let defaultIgnoredApps: [IgnoredApp] = []
  public static let defaultOpenAIModel = "gpt-4o-mini"
  public static let defaultOpenRouterModel = "openai/gpt-4o-mini"

  /// Callback triggered when selection bar enabled state changes.
  @ObservationIgnored
  public var onEnabledChanged: (() -> Void)?

  /// Callback triggered when ignored apps change.
  @ObservationIgnored
  public var onIgnoredAppsChanged: (() -> Void)?

  /// Callback triggered when activation gating mode changes.
  @ObservationIgnored
  public var onActivationRequirementChanged: (() -> Void)?

  /// Cached API key availability for built-in providers.
  public private(set) var openAIAPIKeyConfigured: Bool
  public private(set) var openRouterAPIKeyConfigured: Bool
  public private(set) var deepLAPIKeyConfigured: Bool

  /// Cached API key availability for custom providers by ID.
  public private(set) var customProviderAPIKeyConfiguredByID: [UUID: Bool]

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
      if reconcileCustomActionsAvailabilityIfNeeded() {
        return
      }
      persistIfNeeded()
    }
  }

  /// Configurable text actions.
  public var customActions: [CustomActionConfig] {
    didSet {
      if isReconcilingCustomActions {
        persistIfNeeded()
        return
      }
      if reconcileCustomActionsAvailabilityIfNeeded() {
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
    selectionBarTranslationEnabled = true
    selectionBarTranslationProviderId = SelectionBarTranslationAppProvider.bob.rawValue
    selectionBarIgnoredApps = Self.defaultIgnoredApps
    openAIModel = Self.defaultOpenAIModel
    openAITranslationModel = ""
    availableOpenAIModels = []
    openRouterModel = Self.defaultOpenRouterModel
    openRouterTranslationModel = ""
    availableOpenRouterModels = []
    selectionBarTranslationTargetLanguage = TranslationLanguageCatalog.defaultTargetLanguage
    customLLMProviders = []
    customActions = []
    openAIAPIKeyConfigured = false
    openRouterAPIKeyConfigured = false
    deepLAPIKeyConfigured = false
    customProviderAPIKeyConfiguredByID = [:]

    load()
    refreshCredentialAvailability()
    ensureValidSelectionBarTranslationProvider()
    ensureValidSelectionBarTranslationTargetLanguage()
    _ = reconcileCustomActionsAvailabilityIfNeeded()
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

  public func ensureValidSelectionBarTranslationTargetLanguage() {
    if TranslationLanguageCatalog.contains(code: selectionBarTranslationTargetLanguage) {
      return
    }
    selectionBarTranslationTargetLanguage = TranslationLanguageCatalog.defaultTargetLanguage
  }

  /// Refresh cached API key availability from Keychain.
  public func refreshCredentialAvailability() {
    openAIAPIKeyConfigured = isAPIKeyConfiguredInKeychain("openai_api_key")
    openRouterAPIKeyConfigured = isAPIKeyConfiguredInKeychain("openrouter_api_key")
    deepLAPIKeyConfigured = isAPIKeyConfiguredInKeychain("deepl_api_key")

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
      _ = reconcileCustomActionsAvailabilityIfNeeded()
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
      _ = reconcileCustomActionsAvailabilityIfNeeded()
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
      _ = reconcileCustomActionsAvailabilityIfNeeded()
    }
    persistIfNeeded()
  }

  /// Call this after built-in provider keys are saved/cleared from UI.
  public func handleCredentialChange() {
    withPersistenceSuppressed {
      refreshCredentialAvailability()
      ensureValidSelectionBarTranslationProvider()
      _ = reconcileCustomActionsAvailabilityIfNeeded()
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

  @discardableResult
  public func reconcileCustomActionsAvailabilityIfNeeded() -> Bool {
    let cleanEscapesTemplate = CustomActionConfig.createJavaScriptCleanEscapesTemplate()
    let reconciled = customActions.map { action in
      var updated = migrateLegacyCleanEscapesIconIfNeeded(
        action,
        cleanEscapesTemplate: cleanEscapesTemplate
      )
      guard updated.isEnabled, updated.kind == .llm else { return updated }
      guard canEnableCustomAction(updated) else {
        updated.isEnabled = false
        return updated
      }
      return updated
    }

    guard reconciled != customActions else { return false }
    isReconcilingCustomActions = true
    customActions = reconciled
    isReconcilingCustomActions = false
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
      selectionBarLookupCustomApp: nil,
      selectionBarSearchEngine: selectionBarSearchEngine.rawValue,
      selectionBarTranslationEnabled: selectionBarTranslationEnabled,
      selectionBarTranslationProviderId: selectionBarTranslationProviderId,
      selectionBarIgnoredApps: selectionBarIgnoredApps,
      openAIModel: openAIModel,
      openAITranslationModel: openAITranslationModel,
      availableOpenAIModels: availableOpenAIModels,
      openRouterModel: openRouterModel,
      openRouterTranslationModel: openRouterTranslationModel,
      availableOpenRouterModels: availableOpenRouterModels,
      selectionBarTranslationTargetLanguage: selectionBarTranslationTargetLanguage,
      deepLTargetLanguage: selectionBarTranslationTargetLanguage,
      customLLMProviders: customLLMProviders,
      customActions: customActions
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
      selectionBarTranslationEnabled = settings.selectionBarTranslationEnabled ?? true
      selectionBarTranslationProviderId =
        settings.selectionBarTranslationProviderId
        ?? SelectionBarTranslationAppProvider.bob.rawValue
      selectionBarIgnoredApps = settings.selectionBarIgnoredApps ?? Self.defaultIgnoredApps
      openAIModel = settings.openAIModel ?? Self.defaultOpenAIModel
      openAITranslationModel = settings.openAITranslationModel ?? ""
      availableOpenAIModels = settings.availableOpenAIModels ?? []
      openRouterModel = settings.openRouterModel ?? Self.defaultOpenRouterModel
      openRouterTranslationModel = settings.openRouterTranslationModel ?? ""
      availableOpenRouterModels = settings.availableOpenRouterModels ?? []
      selectionBarTranslationTargetLanguage =
        settings.selectionBarTranslationTargetLanguage
        ?? settings.deepLTargetLanguage
        ?? TranslationLanguageCatalog.defaultTargetLanguage
      customLLMProviders = settings.customLLMProviders ?? []
      customActions = settings.customActions ?? []
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
  let selectionBarLookupCustomApp: IgnoredApp?
  let selectionBarSearchEngine: String?
  let selectionBarTranslationEnabled: Bool?
  let selectionBarTranslationProviderId: String?
  let selectionBarIgnoredApps: [IgnoredApp]?
  let openAIModel: String?
  let openAITranslationModel: String?
  let availableOpenAIModels: [String]?
  let openRouterModel: String?
  let openRouterTranslationModel: String?
  let availableOpenRouterModels: [String]?
  let selectionBarTranslationTargetLanguage: String?
  let deepLTargetLanguage: String?
  let customLLMProviders: [CustomLLMProvider]?
  let customActions: [CustomActionConfig]?
}
