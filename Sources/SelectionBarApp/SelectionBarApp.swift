import AppKit
import SwiftUI

@main
struct SelectionBarApp: App {
  @NSApplicationDelegateAdaptor(SelectionBarAppDelegate.self) var appDelegate

  private static let menuBarIcon: NSImage = {
    guard
      let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
      let image = NSImage(contentsOf: url)
    else {
      preconditionFailure("Missing bundled MenuBarIcon.pdf")
    }
    image.isTemplate = true
    return image
  }()

  var body: some Scene {
    MenuBarExtra {
      MenuBarRootView()
    } label: {
      MenuBarIconView(image: Self.menuBarIcon)
    }

    Settings {
      SettingsRootView()
    }
  }
}

private struct MenuBarRootView: View {
  var body: some View {
    MenuBarContentView(settingsStore: SelectionBarAppManager.shared.appState.settingsStore)
  }
}

private struct SettingsRootView: View {
  @Bindable var state = SelectionBarAppManager.shared.appState
  var body: some View {
    SelectionBarSettingsView(settingsStore: state.settingsStore, selectedTab: $state.settingsTab)
      .frame(minWidth: 760, minHeight: 560)
      .background(
        SettingsWindowFocus(presentation: state.settingsPresentation, tab: state.settingsTab))
  }
}

private struct MenuBarIconView: View {
  let image: NSImage
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Image(nsImage: image)
      .renderingMode(.template)
      .accessibilityLabel("Selection Bar")
      .onAppear {
        let state = SelectionBarAppManager.shared.appState
        state.grammarCoordinator.onOpenSettings = {
          state.settingsTab = .grammar
          state.settingsPresentation += 1
          openSettings()
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
      }
  }
}
