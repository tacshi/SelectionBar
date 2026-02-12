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
    subsystem: "com.selectionbar.app", category: "GeneralSettings"
  )

  @Bindable var settingsStore: SelectionBarSettingsStore
  @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
  @State private var showIgnoredAppPicker = false
  @State private var showRestartAlert = false

  var body: some View {
    @Bindable var settings = settingsStore

    Form {
      Section {
        Toggle("Enable selection bar", isOn: $settings.selectionBarEnabled)
          .help("Show a floating toolbar when text is selected in any app")

        Toggle("Launch at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            do {
              if newValue {
                try LaunchAtLoginManager.enable()
              } else {
                try LaunchAtLoginManager.disable()
              }
            } catch {
              Self.logger.error("Failed to update launch at login: \(error)")
              launchAtLogin = !newValue
            }
          }
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
    }
    .formStyle(.grouped)
    .padding()
    .sheet(isPresented: $showIgnoredAppPicker) {
      AppPickerSheet(
        existingBundleIDs: Set(settings.selectionBarIgnoredApps.map(\.id)),
        onAppsSelected: { newApps in
          settings.selectionBarIgnoredApps.append(contentsOf: newApps)
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

/// Sheet that lists installed applications for the user to select.
private struct AppPickerSheet: View {
  let existingBundleIDs: Set<String>
  let onAppsSelected: ([IgnoredApp]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""
  @State private var discoveredApps: [DiscoveredApp] = []
  @State private var selectedBundleIDs: Set<String> = []

  private struct DiscoveredApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
  }

  private var filteredApps: [DiscoveredApp] {
    if searchText.isEmpty {
      return discoveredApps
    }
    return discoveredApps.filter {
      $0.name.localizedStandardContains(searchText)
        || $0.id.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.escape)
        Spacer()
        Text("Choose Applications")
          .font(.headline)
        Spacer()
        Button("Add") {
          let apps = discoveredApps.filter { selectedBundleIDs.contains($0.id) }
            .map { IgnoredApp(id: $0.id, name: $0.name) }
          onAppsSelected(apps)
          dismiss()
        }
        .keyboardShortcut(.return)
        .disabled(selectedBundleIDs.isEmpty)
      }
      .padding()

      Divider()

      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search", text: $searchText)
          .textFieldStyle(.plain)
      }
      .padding(8)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(.rect(cornerRadius: 8))
      .padding(.horizontal)
      .padding(.top, 8)

      List(filteredApps, selection: $selectedBundleIDs) { app in
        HStack {
          if let icon = app.icon {
            Image(nsImage: icon)
              .resizable()
              .frame(width: 24, height: 24)
          } else {
            Image(systemName: "app")
              .frame(width: 24, height: 24)
          }
          VStack(alignment: .leading, spacing: 1) {
            Text(app.name)
            Text(app.id)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .tag(app.id)
      }
      .listStyle(.bordered)
    }
    .frame(width: 420, height: 450)
    .onAppear {
      discoveredApps = scanApplications()
    }
  }

  /// Scan common app folders for .app bundles.
  private func scanApplications() -> [DiscoveredApp] {
    var apps: [DiscoveredApp] = []
    var seenBundleIDs = Set<String>()

    let searchPaths = [
      "/Applications",
      "/System/Applications",
      NSHomeDirectory().appending("/Applications"),
    ]

    for searchPath in searchPaths {
      let url = URL(filePath: searchPath)
      guard
        let contents = try? FileManager.default.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: nil
        )
      else {
        continue
      }

      for itemURL in contents where itemURL.pathExtension == "app" {
        guard let bundle = Bundle(url: itemURL),
          let bundleID = bundle.bundleIdentifier,
          !existingBundleIDs.contains(bundleID),
          !seenBundleIDs.contains(bundleID)
        else {
          continue
        }

        seenBundleIDs.insert(bundleID)

        let name =
          bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
          ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
          ?? itemURL.deletingPathExtension().lastPathComponent

        let icon = NSWorkspace.shared.icon(forFile: itemURL.path)
        apps.append(DiscoveredApp(id: bundleID, name: name, icon: icon))
      }
    }

    return apps.sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}
