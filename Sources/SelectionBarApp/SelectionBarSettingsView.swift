import AppKit
import SelectionBarCore
import SwiftUI

struct SelectionBarSettingsView: View {
  private enum RootTab: Hashable {
    case selectionBar
    case actions
    case providers
  }

  @Bindable var settingsStore: SelectionBarSettingsStore
  @State private var selectedTab: RootTab = .selectionBar

  var body: some View {
    TabView(selection: $selectedTab) {
      SelectionBarGeneralSettingsTab(settingsStore: settingsStore)
        .tabItem {
          Label("Selection Bar", systemImage: "rectangle.and.hand.point.up.left")
        }
        .tag(RootTab.selectionBar)

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
  @Bindable var settingsStore: SelectionBarSettingsStore
  @State private var showIgnoredAppPicker = false

  var body: some View {
    @Bindable var settings = settingsStore
    let translationProviders = settings.availableSelectionBarTranslationProviders()
    let appTranslationProviders = translationProviders.filter { $0.kind == .app }
    let llmTranslationProviders = translationProviders.filter { $0.kind == .llm }

    Form {
      Section {
        Toggle("Enable selection bar", isOn: $settings.selectionBarEnabled)
          .help("Show a floating toolbar when text is selected in any app")

        Text(
          "Includes built-in Copy, Cut, Web Search, Open URL, Look Up, and app-based Translate actions."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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
        Text("When enabled, Selection Bar appears only while the selected modifier key is held.")
      }

      Section {
        Picker("Engine", selection: $settings.selectionBarSearchEngine) {
          Text("Google").tag(SelectionBarSearchEngine.google)
          Text("Baidu").tag(SelectionBarSearchEngine.baidu)
          Text("Sogou").tag(SelectionBarSearchEngine.sogou)
          Text("360 Search").tag(SelectionBarSearchEngine.so360)
          Text("Bing").tag(SelectionBarSearchEngine.bing)
          Text("Yandex").tag(SelectionBarSearchEngine.yandex)
          Text("DuckDuckGo").tag(SelectionBarSearchEngine.duckDuckGo)
        }
      } header: {
        Label("Web Search", systemImage: "magnifyingglass")
      }

      Section {
        Toggle("Enable Look Up", isOn: $settings.selectionBarLookupEnabled)

        if settings.selectionBarLookupEnabled {
          Picker("Dictionary", selection: $settings.selectionBarLookupProvider) {
            Text("Dictionary (macOS)").tag(SelectionBarLookupProvider.systemDictionary)
            Text("Eudic").tag(SelectionBarLookupProvider.eudic)
            Text("Custom URL Scheme").tag(SelectionBarLookupProvider.customApp)
          }

          if settings.selectionBarLookupProvider == .customApp {
            TextField("URL Scheme", text: $settings.selectionBarLookupCustomScheme)
              .textFieldStyle(.roundedBorder)

            Text("Enter a scheme like eudic, or a URL template with {{query}}.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Label("Word Lookup", systemImage: "book.closed")
      }

      Section {
        Toggle("Enable Translate", isOn: $settings.selectionBarTranslationEnabled)

        if settings.selectionBarTranslationEnabled {
          if translationProviders.isEmpty {
            Text("No translation providers configured")
              .foregroundStyle(.secondary)
          } else {
            Picker("Provider", selection: $settings.selectionBarTranslationProviderId) {
              ForEach(appTranslationProviders, id: \.id) { provider in
                Text(provider.name).tag(provider.id)
              }
              if !appTranslationProviders.isEmpty && !llmTranslationProviders.isEmpty {
                Divider()
              }
              ForEach(llmTranslationProviders, id: \.id) { provider in
                Text(provider.name).tag(provider.id)
              }
            }

            if settings.isSelectionBarLLMTranslationProvider(
              id: settings.selectionBarTranslationProviderId
            ) {
              Picker("Target", selection: $settings.selectionBarTranslationTargetLanguage) {
                ForEach(TranslationLanguageCatalog.targetLanguages) { language in
                  Text(language.localizedName).tag(language.code)
                }
              }
            }
          }
        }
      } header: {
        Label("Translation", systemImage: "translate")
      } footer: {
        Text("Translate supports app providers and LLM providers. Target applies to LLM providers.")
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
    .onAppear {
      settings.ensureValidSelectionBarTranslationProvider()
    }
    .onChange(of: settings.customLLMProviders) { _, _ in
      settings.ensureValidSelectionBarTranslationProvider()
    }
    .onChange(of: settings.availableOpenAIModels) { _, _ in
      settings.ensureValidSelectionBarTranslationProvider()
    }
    .onChange(of: settings.availableOpenRouterModels) { _, _ in
      settings.ensureValidSelectionBarTranslationProvider()
    }
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
