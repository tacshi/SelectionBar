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
      Image(nsImage: Self.menuBarIcon)
        .renderingMode(.template)
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
