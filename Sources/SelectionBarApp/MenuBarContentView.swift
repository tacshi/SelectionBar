import AppKit
import SelectionBarCore
import SwiftUI

struct MenuBarContentView: View {
  @Environment(\.openSettings) private var openSettings
  @Bindable var settingsStore: SelectionBarSettingsStore

  var body: some View {
    @Bindable var settings = settingsStore

    VStack(alignment: .leading) {
      Button(Self.enableButtonTitle(isEnabled: settings.selectionBarEnabled)) {
        settings.selectionBarEnabled.toggle()
      }

      Divider()

      Button(action: {
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
          // Allow SwiftUI to create/attach the settings window first.
          await Task.yield()
          focusSettingsWindowIfPresent()
          await Task.yield()
          focusSettingsWindowIfPresent()
        }
      }) {
        Label("Settings", systemImage: "gearshape")
      }

      Button(action: {
        SelectionBarAppManager.shared.updaterManager.checkForUpdates()
      }) {
        Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(!SelectionBarAppManager.shared.updaterManager.canCheckForUpdates)

      Button(
        "Quit", systemImage: "power",
        action: {
          NSApp.terminate(nil)
        })
    }
    .padding()
    .frame(minWidth: 300, alignment: .leading)
  }

  @MainActor
  private func focusSettingsWindowIfPresent() {
    let windows = NSApplication.shared.windows
    if let settingsWindow = windows.first(where: isLikelySettingsWindow)
      ?? windows.first(where: { $0.canBecomeKey && !$0.isMiniaturized })
    {
      settingsWindow.orderFrontRegardless()
      settingsWindow.makeKeyAndOrderFront(nil)
    }
  }

  private func isLikelySettingsWindow(_ window: NSWindow) -> Bool {
    if let identifier = window.identifier?.rawValue,
      identifier.localizedStandardContains("settings")
    {
      return true
    }
    return window.title.localizedStandardContains("Settings")
  }

  static func enableButtonTitle(isEnabled: Bool) -> String {
    isEnabled ? "Disable" : "Enable"
  }
}
