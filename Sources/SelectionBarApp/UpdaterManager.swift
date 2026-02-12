import Foundation
import Sparkle

@MainActor
@Observable
final class UpdaterManager: NSObject {
  private var updaterController: SPUStandardUpdaterController!

  private(set) var canCheckForUpdates = false

  private var canCheckForUpdatesObservation: NSKeyValueObservation?

  override init() {
    super.init()

    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )

    canCheckForUpdatesObservation = updaterController.updater.observe(
      \.canCheckForUpdates,
      options: [.initial, .new]
    ) { [weak self] _, change in
      let newValue = change.newValue ?? false
      Task { @MainActor [weak self] in
        self?.canCheckForUpdates = newValue
      }
    }
  }

  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
  }

  func checkForUpdatesInBackground() {
    updaterController.updater.checkForUpdatesInBackground()
  }
}
