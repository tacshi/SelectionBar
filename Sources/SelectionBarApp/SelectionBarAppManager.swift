import AppKit
import PermissionFlowInputMonitoringStatus

@MainActor
final class SelectionBarAppManager {
  static let shared = SelectionBarAppManager()

  let appState = SelectionBarAppState()
  let updaterManager = UpdaterManager()

  private init() {}
}

@MainActor
final class SelectionBarAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    PermissionFlowInputMonitoringStatus.register()
    SelectionBarAppManager.shared.updaterManager.checkForUpdatesInBackground()
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Settings writes are coalesced; make sure the last edit lands on disk.
    SelectionBarAppManager.shared.appState.settingsStore.flushPendingWrites()
  }
}
