import AppKit
import SwiftUI

@main
struct SelectionBarApp: App {
  @NSApplicationDelegateAdaptor(SelectionBarAppDelegate.self) var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarRootView()
    } label: {
      Image(systemName: "rectangle.and.hand.point.up.left")
        .accessibilityLabel("Selection Bar")
    }

    Settings {
      SelectionBarSettingsView(settingsStore: SelectionBarAppManager.shared.appState.settingsStore)
        .frame(minWidth: 760, minHeight: 560)
    }
  }
}

private struct MenuBarRootView: View {
  var body: some View {
    MenuBarContentView(settingsStore: SelectionBarAppManager.shared.appState.settingsStore)
  }
}
