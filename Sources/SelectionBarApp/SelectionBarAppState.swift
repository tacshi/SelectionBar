import Observation
import SelectionBarCore

@MainActor
@Observable
final class SelectionBarAppState {
  let settingsStore = SelectionBarSettingsStore()

  @ObservationIgnored
  lazy var coordinator = SelectionBarCoordinator(settingsStore: settingsStore)

  init() {
    _ = coordinator

    settingsStore.onEnabledChanged = { [weak self] in
      self?.coordinator.updateEnabled()
    }
    settingsStore.onIgnoredAppsChanged = { [weak self] in
      self?.coordinator.updateIgnoredApps()
    }
    settingsStore.onActivationRequirementChanged = { [weak self] in
      self?.coordinator.updateActivationRequirement()
    }
  }
}
