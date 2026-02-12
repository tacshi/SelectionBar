import AppKit

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
    SelectionBarAppManager.shared.updaterManager.checkForUpdatesInBackground()
  }
}
