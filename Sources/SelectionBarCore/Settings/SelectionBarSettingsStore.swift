import AppKit
import Foundation
import Observation

public enum CustomActionEnablementIssue: Sendable, Equatable {
  case missingProvider
  case missingModel
  case providerUnavailable
  case emptyPipeline
  case missingPipelineStep
  case invalidPipelineStep
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
  @ObservationIgnored
  private var pendingSaveTask: Task<Void, Never>?

  private static let saveCoalescingInterval = Duration.milliseconds(250)

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

  /// Per-app overrides for configurable Selection Bar actions.
  public var actionProfiles: [SelectionBarActionProfile] {
    didSet { persistIfNeeded() }
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
    actionProfiles = []
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

  /// All actions that can be included in an app-specific action profile.
  public var actionProfileAvailableActions: [CustomActionConfig] {
    builtInKeyBindingActions + customActions.filter { $0.kind != .keyBinding }
  }

  /// Enabled action list for a frontmost app. Matching enabled profiles replace the global list.
  public func orderedEnabledSelectionBarActions(for bundleID: String?) -> [CustomActionConfig] {
    guard
      let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !bundleID.isEmpty,
      let profile = actionProfiles.first(where: { profile in
        profile.isEnabled && profile.app.id == bundleID
      })
    else {
      return orderedEnabledSelectionBarActions
    }

    return profile.actionIDs.compactMap { actionID in
      guard let action = actionProfileAction(id: actionID) else { return nil }
      return isValidActionProfileAction(action) ? action : nil
    }
  }

  public func actionProfileStatus(
    _ profile: SelectionBarActionProfile
  ) -> SelectionBarActionProfileStatus {
    var validActionCount = 0
    var missingActionCount = 0
    var invalidActionCount = 0

    for actionID in profile.actionIDs {
      guard let action = actionProfileAction(id: actionID) else {
        missingActionCount += 1
        continue
      }

      if isValidActionProfileAction(action) {
        validActionCount += 1
      } else {
        invalidActionCount += 1
      }
    }

    return SelectionBarActionProfileStatus(
      validActionCount: validActionCount,
      missingActionCount: missingActionCount,
      invalidActionCount: invalidActionCount
    )
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
    customActionEnablementIssue(action) == nil
  }

  public func customActionEnablementIssue(
    _ action: CustomActionConfig
  ) -> CustomActionEnablementIssue? {
    customActionEnablementIssue(action, checkProviderAvailability: true)
  }

  private func customActionEnablementIssue(
    _ action: CustomActionConfig,
    checkProviderAvailability: Bool
  ) -> CustomActionEnablementIssue? {
    switch action.kind {
    case .javascript:
      return nil
    case .llm:
      return llmActionEnablementIssue(
        action,
        checkProviderAvailability: checkProviderAvailability
      )
    case .keyBinding:
      return isValidKeyBindingAction(action) ? nil : .invalidPipelineStep
    case .pipeline:
      return pipelineActionEnablementIssue(
        action,
        checkProviderAvailability: checkProviderAvailability
      )
    }
  }

  public func llmActionEnablementIssue(_ action: CustomActionConfig) -> CustomActionEnablementIssue?
  {
    llmActionEnablementIssue(action, checkProviderAvailability: true)
  }

  private func llmActionEnablementIssue(
    _ action: CustomActionConfig,
    checkProviderAvailability: Bool
  ) -> CustomActionEnablementIssue? {
    guard action.kind == .llm else { return nil }

    let provider = action.modelProvider.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !provider.isEmpty else { return .missingProvider }

    let model = action.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else { return .missingModel }

    guard !checkProviderAvailability || isAvailableLLMProvider(providerID: provider) else {
      return .providerUnavailable
    }
    return nil
  }

  public func pipelineActionEnablementIssue(
    _ action: CustomActionConfig
  ) -> CustomActionEnablementIssue? {
    pipelineActionEnablementIssue(action, checkProviderAvailability: true)
  }

  private func pipelineActionEnablementIssue(
    _ action: CustomActionConfig,
    checkProviderAvailability: Bool
  ) -> CustomActionEnablementIssue? {
    guard action.kind == .pipeline else { return nil }
    guard !action.pipelineSteps.isEmpty else { return .emptyPipeline }

    for step in action.pipelineSteps {
      guard let stepAction = customActions.first(where: { $0.id == step.actionID }) else {
        return .missingPipelineStep
      }
      guard stepAction.id != action.id else { return .invalidPipelineStep }

      switch stepAction.kind {
      case .javascript:
        continue
      case .llm:
        if llmActionEnablementIssue(
          stepAction,
          checkProviderAvailability: checkProviderAvailability
        ) != nil {
          return .invalidPipelineStep
        }
      case .keyBinding, .pipeline:
        return .invalidPipelineStep
      }
    }

    return nil
  }

  public func actionNeedsSourceContext(_ action: CustomActionConfig) -> Bool {
    switch action.kind {
    case .llm:
      return action.includesSourceContext
    case .pipeline:
      return action.pipelineSteps.contains { step in
        guard let stepAction = customActions.first(where: { $0.id == step.actionID }) else {
          return false
        }
        return stepAction.kind == .llm && stepAction.includesSourceContext
      }
    case .javascript, .keyBinding:
      return false
    }
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
        if llmActionEnablementIssue(
          updated,
          checkProviderAvailability: checkProviderAvailability
        ) != nil {
          updated.isEnabled = false
        }
        return updated
      case .pipeline:
        if customActionEnablementIssue(
          updated,
          checkProviderAvailability: checkProviderAvailability
        ) != nil {
          updated.isEnabled = false
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

  /// Single source of truth binding each persisted property to its
  /// `StoredSettings` field, default value, and load-time sanitizer.
  ///
  /// Adding a setting means adding a stored property, a `StoredSettings`
  /// field, and one row here. Omitting the row is the only remaining way to
  /// forget persistence, and omitting the `StoredSettings` field is a
  /// compile error.
  private static let persistedFields: [PersistedField] = [
    bind(\.selectionBarEnabled, \.selectionBarEnabled, default: false),
    bind(\.selectionBarDoNotDisturbEnabled, \.selectionBarDoNotDisturbEnabled, default: false),
    bind(\.selectionBarActivationModifier, \.selectionBarActivationModifier, default: .option),
    bind(\.selectionBarLookupEnabled, \.selectionBarLookupEnabled, default: true),
    bind(\.selectionBarLookupProvider, \.selectionBarLookupProvider, default: .systemDictionary),
    bind(\.selectionBarLookupCustomScheme, \.selectionBarLookupCustomScheme, default: ""),
    bind(\.selectionBarSearchEngine, \.selectionBarSearchEngine, default: .google),
    bind(\.selectionBarSearchCustomScheme, \.selectionBarSearchCustomScheme, default: ""),
    bind(\.selectionBarTerminalApp, \.selectionBarTerminalApp, default: .terminal),
    bind(\.selectionBarSpeakEnabled, \.selectionBarSpeakEnabled, default: true),
    bind(\.selectionBarSpeakVoiceIdentifier, \.selectionBarSpeakVoiceIdentifier, default: ""),
    bind(
      \.selectionBarSpeakProviderId, \.selectionBarSpeakProviderId,
      default: SelectionBarSpeakSystemProvider.apple.rawValue),
    bind(\.elevenLabsVoiceId, \.elevenLabsVoiceId, default: ""),
    bind(\.elevenLabsModelId, \.elevenLabsModelId, default: "eleven_v3"),
    bind(\.availableElevenLabsVoices, \.availableElevenLabsVoices, default: []),
    bind(\.selectionBarChatEnabled, \.selectionBarChatEnabled, default: false),
    bind(\.selectionBarChatProviderId, \.selectionBarChatProviderId, default: ""),
    bind(\.selectionBarChatModelId, \.selectionBarChatModelId, default: ""),
    bind(\.selectionBarChatSessionLimit, \.selectionBarChatSessionLimit, default: 50),
    bind(\.selectionBarTranslationEnabled, \.selectionBarTranslationEnabled, default: true),
    bind(
      \.selectionBarTranslationProviderId, \.selectionBarTranslationProviderId,
      default: SelectionBarTranslationAppProvider.bob.rawValue),
    bind(\.selectionBarIgnoredApps, \.selectionBarIgnoredApps, default: defaultIgnoredApps),
    bind(
      \.selectionBarClipboardFallbackIncludedApps, \.selectionBarClipboardFallbackIncludedApps,
      default: defaultClipboardFallbackIncludedApps),
    bind(\.openAIModel, \.openAIModel, default: defaultOpenAIModel),
    bind(\.openAITranslationModel, \.openAITranslationModel, default: ""),
    bind(\.availableOpenAIModels, \.availableOpenAIModels, default: []),
    bind(\.openRouterModel, \.openRouterModel, default: defaultOpenRouterModel),
    bind(\.openRouterTranslationModel, \.openRouterTranslationModel, default: ""),
    bind(\.availableOpenRouterModels, \.availableOpenRouterModels, default: []),
    bind(
      \.selectionBarTranslationTargetLanguage, \.selectionBarTranslationTargetLanguage,
      default: TranslationLanguageCatalog.defaultTargetLanguage),
    bind(\.customLLMProviders, \.customLLMProviders, default: []),
    bind(
      \.customActions, \.customActions, default: [],
      sanitize: { $0.filter { action in action.kind != .keyBinding } }),
    bind(
      \.builtInKeyBindingActions, \.builtInKeyBindingActions, default: [],
      sanitize: { $0.filter { action in action.kind == .keyBinding } }),
    bind(\.actionProfiles, \.actionProfiles, default: []),
  ]

  /// One persisted setting, reduced to a capture/apply pair.
  private struct PersistedField {
    let capture: @MainActor (SelectionBarSettingsStore, inout StoredSettings) -> Void
    let apply: @MainActor (StoredSettings, SelectionBarSettingsStore) -> Void
  }

  /// Binds a property whose in-memory type is stored verbatim in the payload.
  private static func bind<Value>(
    _ property: ReferenceWritableKeyPath<SelectionBarSettingsStore, Value>,
    _ stored: WritableKeyPath<StoredSettings, Value?>,
    default defaultValue: @autoclosure @escaping @MainActor () -> Value,
    sanitize: @escaping @MainActor (Value) -> Value = { $0 }
  ) -> PersistedField {
    PersistedField(
      capture: { store, payload in
        payload[keyPath: stored] = store[keyPath: property]
      },
      apply: { payload, store in
        store[keyPath: property] = sanitize(payload[keyPath: stored] ?? defaultValue())
      }
    )
  }

  /// Binds an enum property persisted as its `rawValue`, falling back to
  /// `defaultValue` when the field is missing or holds an unknown case.
  private static func bind<Value: RawRepresentable>(
    _ property: ReferenceWritableKeyPath<SelectionBarSettingsStore, Value>,
    _ stored: WritableKeyPath<StoredSettings, String?>,
    default defaultValue: Value
  ) -> PersistedField where Value.RawValue == String {
    PersistedField(
      capture: { store, payload in
        payload[keyPath: stored] = store[keyPath: property].rawValue
      },
      apply: { payload, store in
        store[keyPath: property] = Value(rawValue: payload[keyPath: stored] ?? "") ?? defaultValue
      }
    )
  }

  private func save() {
    var data = StoredSettings()
    for field in Self.persistedFields {
      field.capture(self, &data)
    }

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
      for field in Self.persistedFields {
        field.apply(settings, self)
      }
    }
  }

  private func withPersistenceSuppressed(_ operation: () -> Void) {
    persistenceSuppressionDepth += 1
    defer { persistenceSuppressionDepth = max(0, persistenceSuppressionDepth - 1) }
    operation()
  }

  private func persistIfNeeded() {
    guard persistenceSuppressionDepth == 0 else { return }
    scheduleSave()
  }

  /// Every `didSet` re-encodes the whole settings blob — including custom
  /// actions, providers and cached model lists — so a text field bound to a
  /// setting would otherwise write the entire payload on each keystroke.
  /// Coalesce instead, and flush on the paths that need durability.
  private func scheduleSave() {
    pendingSaveTask?.cancel()
    pendingSaveTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Self.saveCoalescingInterval)
      guard !Task.isCancelled, let self else { return }
      self.pendingSaveTask = nil
      self.save()
    }
  }

  /// Writes any coalesced changes immediately. Call before the process can go
  /// away, and from tests that read the persisted payload back.
  public func flushPendingWrites() {
    guard pendingSaveTask != nil else { return }
    pendingSaveTask?.cancel()
    pendingSaveTask = nil
    save()
  }

  private func actionProfileAction(id: UUID) -> CustomActionConfig? {
    builtInKeyBindingActions.first { $0.id == id }
      ?? customActions.first { $0.id == id }
  }

  private func isValidActionProfileAction(_ action: CustomActionConfig) -> Bool {
    switch action.kind {
    case .keyBinding:
      guard builtInKeyBindingActions.contains(where: { $0.id == action.id }) else {
        return false
      }
    case .javascript, .llm, .pipeline:
      break
    }
    return customActionEnablementIssue(action) == nil
  }
}

/// Codable persistence payload. Field names and order define the on-disk JSON;
/// every field is optional so older payloads decode with per-field defaults.
private struct StoredSettings: Codable {
  var selectionBarEnabled: Bool?
  var selectionBarDoNotDisturbEnabled: Bool?
  var selectionBarActivationModifier: String?
  var selectionBarLookupEnabled: Bool?
  var selectionBarLookupProvider: String?
  var selectionBarLookupCustomScheme: String?
  var selectionBarSearchEngine: String?
  var selectionBarSearchCustomScheme: String?
  var selectionBarTerminalApp: String?
  var selectionBarSpeakEnabled: Bool?
  var selectionBarSpeakVoiceIdentifier: String?
  var selectionBarSpeakProviderId: String?
  var elevenLabsVoiceId: String?
  var elevenLabsModelId: String?
  var availableElevenLabsVoices: [ElevenLabsVoice]?
  var selectionBarChatEnabled: Bool?
  var selectionBarChatProviderId: String?
  var selectionBarChatModelId: String?
  var selectionBarChatSessionLimit: Int?
  var selectionBarTranslationEnabled: Bool?
  var selectionBarTranslationProviderId: String?
  var selectionBarIgnoredApps: [IgnoredApp]?
  var selectionBarClipboardFallbackIncludedApps: [IgnoredApp]?
  var openAIModel: String?
  var openAITranslationModel: String?
  var availableOpenAIModels: [String]?
  var openRouterModel: String?
  var openRouterTranslationModel: String?
  var availableOpenRouterModels: [String]?
  var selectionBarTranslationTargetLanguage: String?
  var customLLMProviders: [CustomLLMProvider]?
  var customActions: [CustomActionConfig]?
  var builtInKeyBindingActions: [CustomActionConfig]?
  var actionProfiles: [SelectionBarActionProfile]?
}
