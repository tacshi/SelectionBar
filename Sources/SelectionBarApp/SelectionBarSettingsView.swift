import AppKit
import OSLog
import SelectionBarCore
import SwiftUI

struct SelectionBarSettingsView: View {
  private enum RootTab: Hashable {
    case general
    case actions
    case providers
  }

  @Bindable var settingsStore: SelectionBarSettingsStore
  @State private var selectedTab: RootTab = .general

  var body: some View {
    TabView(selection: $selectedTab) {
      SelectionBarGeneralSettingsTab(settingsStore: settingsStore)
        .tabItem {
          Label("General", systemImage: "gearshape")
        }
        .tag(RootTab.general)

      SelectionBarActionsSettingsTab(settingsStore: settingsStore)
        .tabItem {
          Label("Actions", systemImage: "bolt.circle")
        }
        .tag(RootTab.actions)

      SelectionBarProvidersSettingsTab(settingsStore: settingsStore)
        .tabItem {
          Label("Providers", systemImage: "server.rack")
        }
        .tag(RootTab.providers)
    }
    .frame(minWidth: 760, minHeight: 560)
  }
}

private struct SelectionBarGeneralSettingsTab: View {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.selectionbar.app",
    category: "GeneralSettings"
  )

  @Bindable var settingsStore: SelectionBarSettingsStore
  @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
  @State private var showIgnoredAppPicker = false
  @State private var showClipboardFallbackIncludedAppPicker = false
  @State private var showRestartAlert = false

  var body: some View {
    @Bindable var settings = settingsStore

    Form {
      Section {
        Toggle("Enable selection bar", isOn: $settings.selectionBarEnabled)
          .help("Show a floating toolbar when text is selected in any app")

        Toggle("Launch at Login", isOn: launchAtLoginBinding)
      }

      Section {
        Toggle(
          "Enable Do Not Disturb Mode",
          isOn: $settings.selectionBarDoNotDisturbEnabled
        )

        if settings.selectionBarDoNotDisturbEnabled {
          Picker("Hold Key", selection: $settings.selectionBarActivationModifier) {
            ForEach(SelectionBarActivationModifier.allCases, id: \.self) { modifier in
              Text(modifier.displayName).tag(modifier)
            }
          }
        }
      } header: {
        Label("Activation", systemImage: "moon.zzz")
      } footer: {
        Text(
          "When enabled, Selection Bar appears only while the selected modifier key is held."
        )
      }

      Section {
        Picker("Language", selection: $settings.appLanguage) {
          Text("System Default").tag("")
          Text("English").tag("en")
          Text("日本語").tag("ja")
          Text("简体中文").tag("zh-Hans")
        }
        .onChange(of: settings.appLanguage) { _, _ in
          showRestartAlert = true
        }
      } header: {
        Label("Language", systemImage: "globe")
      }

      Section {
        if settings.selectionBarIgnoredApps.isEmpty {
          Text("No ignored apps")
            .foregroundStyle(.secondary)
        } else {
          ForEach(settings.selectionBarIgnoredApps) { app in
            HStack {
              AppIconView(bundleID: app.id)
                .frame(width: 20, height: 20)
              Text(app.name)
              Spacer()
              Text(app.id)
                .font(.caption)
                .foregroundStyle(.tertiary)
              Button(
                "Remove", systemImage: "minus.circle.fill",
                action: {
                  settings.selectionBarIgnoredApps.removeAll { $0.id == app.id }
                }
              )
              .labelStyle(.iconOnly)
              .buttonStyle(.plain)
              .foregroundStyle(.red)
              .help("Remove")
            }
          }
        }

        Button(
          "Add Application", systemImage: "plus.circle",
          action: {
            showIgnoredAppPicker = true
          })
      } header: {
        Label("Ignored Apps", systemImage: "nosign")
      } footer: {
        Text("The selection bar won't appear when these apps are in the foreground.")
      }

      Section {
        if settings.selectionBarClipboardFallbackIncludedApps.isEmpty {
          Text("No included apps")
            .foregroundStyle(.secondary)
        } else {
          ForEach(settings.selectionBarClipboardFallbackIncludedApps) { app in
            HStack {
              AppIconView(bundleID: app.id)
                .frame(width: 20, height: 20)
              Text(app.name)
              Spacer()
              Text(app.id)
                .font(.caption)
                .foregroundStyle(.tertiary)
              Button(
                "Remove", systemImage: "minus.circle.fill",
                action: {
                  settings.selectionBarClipboardFallbackIncludedApps.removeAll { $0.id == app.id }
                }
              )
              .labelStyle(.iconOnly)
              .buttonStyle(.plain)
              .foregroundStyle(.red)
              .help("Remove")
            }
          }
        }

        Button(
          "Add Application", systemImage: "plus.circle",
          action: {
            showClipboardFallbackIncludedAppPicker = true
          })
      } header: {
        Label("Included Apps", systemImage: "text.badge.plus")
      } footer: {
        Text(
          "Use this for apps where text selection works with Cmd+C but Accessibility does not expose selected text directly. SelectionBar will allow a stricter clipboard fallback for these apps. Known apps such as WeChat and Telegram are only prefilled when they are installed."
        )
      }
    }
    .formStyle(.grouped)
    .padding()
    .sheet(isPresented: $showIgnoredAppPicker) {
      ApplicationPickerSheet(
        existingBundleIDs: Set(
          settings.selectionBarIgnoredApps.map(\.id)
            + settings.selectionBarClipboardFallbackIncludedApps.map(\.id)
        ),
        onAppsSelected: { newApps in
          settings.selectionBarIgnoredApps.append(contentsOf: newApps)
        }
      )
    }
    .sheet(isPresented: $showClipboardFallbackIncludedAppPicker) {
      ApplicationPickerSheet(
        existingBundleIDs: Set(
          settings.selectionBarClipboardFallbackIncludedApps.map(\.id)
            + settings.selectionBarIgnoredApps.map(\.id)
        ),
        onAppsSelected: { newApps in
          settings.selectionBarClipboardFallbackIncludedApps.append(contentsOf: newApps)
        }
      )
    }
    .alert("Restart Required", isPresented: $showRestartAlert) {
      Button("Restart Now") {
        restartApp()
      }
      Button("Later", role: .cancel) {}
    } message: {
      Text("The language change will take effect after restarting SelectionBar.")
    }
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { launchAtLogin },
      set: { newValue in
        do {
          if newValue {
            try LaunchAtLoginManager.enable()
          } else {
            try LaunchAtLoginManager.disable()
          }
          launchAtLogin = newValue
        } catch {
          Self.logger.error("Failed to update launch at login: \(error)")
        }
      }
    )
  }

  private func restartApp() {
    let appPath = Bundle.main.bundleURL.path
    let pid = ProcessInfo.processInfo.processIdentifier
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = [
      "-c",
      "while kill -0 $1 2>/dev/null; do sleep 0.1; done; open -- \"$2\"",
      "sh",
      "\(pid)",
      appPath,
    ]

    do {
      try task.run()
      if task.isRunning {
        NSApplication.shared.terminate(nil)
      } else {
        showRestartFailureAlert()
      }
    } catch {
      showRestartFailureAlert()
    }
  }

  private func showRestartFailureAlert() {
    let alert = NSAlert()
    alert.messageText = "Restart Failed"
    alert.informativeText =
      "SelectionBar could not restart automatically. Please relaunch it manually."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

private struct SelectionBarProvidersSettingsTab: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  var body: some View {
    ProvidersSettingsSections(settingsStore: settingsStore)
  }
}

private struct SelectionBarActionsSettingsTab: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  var body: some View {
    ActionsSettingsSections(settingsStore: settingsStore)
  }
}

/// Displays an app icon resolved from its bundle identifier.
private struct AppIconView: View {
  let bundleID: String

  var body: some View {
    if let image = resolveIcon() {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else {
      Image(systemName: "app")
        .foregroundStyle(.secondary)
    }
  }

  private func resolveIcon() -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return nil
    }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
}
