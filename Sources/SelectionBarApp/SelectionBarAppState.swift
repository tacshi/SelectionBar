import Observation
import SelectionBarCore

@MainActor
@Observable
final class SelectionBarAppState {
  let settingsStore = SelectionBarSettingsStore()
  var settingsTab: SelectionBarSettingsTab = .general
  var settingsPresentation = 0

  @ObservationIgnored
  lazy var coordinator = SelectionBarCoordinator(settingsStore: settingsStore)

  @ObservationIgnored
  lazy var grammarCoordinator = GrammarCoordinator(settingsStore: settingsStore)

  init() {
    _ = coordinator
    _ = grammarCoordinator

    settingsStore.onEnabledChanged = { [weak self] in
      self?.coordinator.updateEnabled()
    }
    settingsStore.onIgnoredAppsChanged = { [weak self] in
      self?.coordinator.updateIgnoredApps()
    }
    settingsStore.onClipboardFallbackIncludedAppsChanged = { [weak self] in
      self?.coordinator.updateClipboardFallbackIncludedApps()
    }
    settingsStore.onActivationRequirementChanged = { [weak self] in
      self?.coordinator.updateActivationRequirement()
    }
  }
}
