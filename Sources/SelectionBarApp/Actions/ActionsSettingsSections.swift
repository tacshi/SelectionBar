import AppKit
import SelectionBarCore
import SwiftUI

private enum ActionsTab: Hashable {
  case builtIn
  case custom
  case profiles
}

private enum ActionEditorDestination: Hashable {
  case customActions
  case builtInKeyBindingActions
}

private struct ActionsEditorItem: Identifiable {
  let destination: ActionEditorDestination
  let mode: ActionEditorMode
  let config: CustomActionConfig

  var id: UUID { config.id }
}

private struct ActionProfileEditorItem: Identifiable {
  let profile: SelectionBarActionProfile

  var id: UUID { profile.id }
}

private struct ActionProfileAppIconView: View {
  let bundleID: String
  let size: CGFloat

  var body: some View {
    if let image = resolveIcon() {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    } else {
      Image(systemName: "app")
        .font(.system(size: size * 0.7))
        .foregroundStyle(.secondary)
        .frame(width: size, height: size)
    }
  }

  private func resolveIcon() -> NSImage? {
    guard !bundleID.isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else {
      return nil
    }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
}

struct ActionsSettingsSections: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  @State private var selectedTab: ActionsTab? = .builtIn
  @State private var editingAction: ActionsEditorItem?
  @State private var editingProfile: ActionProfileEditorItem?

  private var llmTemplates: [CustomActionConfig] {
    CustomActionConfig.createAllBuiltInTemplates()
  }

  private var keyBindingTemplates: [CustomActionConfig] {
    CustomActionConfig.createKeyBindingStarterTemplates()
  }

  private var javaScriptTemplates: [CustomActionConfig] {
    CustomActionConfig.createJavaScriptStarterTemplates()
  }

  var body: some View {
    HStack(spacing: 0) {
      List(selection: $selectedTab) {
        Label("Built-in", systemImage: "tray.full")
          .tag(ActionsTab.builtIn)

        Label("Custom", systemImage: "square.and.pencil")
          .tag(ActionsTab.custom)

        Label("Profiles", systemImage: "person.crop.square")
          .tag(ActionsTab.profiles)
      }
      .frame(width: 180)
      .listStyle(.sidebar)

      Divider()

      Group {
        switch selectedTab {
        case .builtIn:
          ActionsBuiltInSettingsContent(
            settingsStore: settingsStore,
            editingAction: $editingAction,
            keyBindingTemplates: keyBindingTemplates
          )
        case .custom:
          ActionsCustomSettingsContent(
            settingsStore: settingsStore,
            editingAction: $editingAction,
            llmTemplates: llmTemplates,
            javaScriptTemplates: javaScriptTemplates
          )
        case .profiles:
          ActionsProfilesSettingsContent(
            settingsStore: settingsStore,
            editingProfile: $editingProfile
          )
        case .none:
          ActionsBuiltInSettingsContent(
            settingsStore: settingsStore,
            editingAction: $editingAction,
            keyBindingTemplates: keyBindingTemplates
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .sheet(item: $editingAction) { item in
      ActionsCustomActionEditorView(
        settingsStore: settingsStore,
        mode: item.mode,
        config: item.config,
        onSave: { newConfig in
          switch item.destination {
          case .customActions:
            if let existingIndex = settingsStore.customActions.firstIndex(where: {
              $0.id == newConfig.id
            }) {
              settingsStore.customActions[existingIndex] = newConfig
            } else {
              settingsStore.customActions.append(newConfig)
            }
          case .builtInKeyBindingActions:
            var normalized = newConfig
            normalized.kind = .keyBinding
            normalized.outputMode = .resultWindow
            normalized.modelProvider = ""
            normalized.modelId = ""
            normalized.script = CustomActionConfig.defaultJavaScriptTemplate

            if let existingIndex = settingsStore.builtInKeyBindingActions.firstIndex(where: {
              $0.id == normalized.id
            }) {
              settingsStore.builtInKeyBindingActions[existingIndex] = normalized
            } else {
              settingsStore.builtInKeyBindingActions.append(normalized)
            }
          }
          editingAction = nil
        },
        onCancel: { editingAction = nil }
      )
    }
    .sheet(item: $editingProfile) { item in
      ActionProfileEditorView(
        settingsStore: settingsStore,
        profile: item.profile,
        onSave: { profile in
          if let existingIndex = settingsStore.actionProfiles.firstIndex(where: {
            $0.id == profile.id
          }) {
            settingsStore.actionProfiles[existingIndex] = profile
          } else {
            settingsStore.actionProfiles.append(profile)
          }
          editingProfile = nil
        },
        onCancel: { editingProfile = nil }
      )
    }
  }
}

private struct ActionsBuiltInSettingsContent: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  @Binding var editingAction: ActionsEditorItem?
  let keyBindingTemplates: [CustomActionConfig]

  var body: some View {
    @Bindable var settings = settingsStore
    let translationProviders = settings.availableSelectionBarTranslationProviders()
    let appTranslationProviders = translationProviders.filter { $0.kind == .app }
    let llmTranslationProviders = translationProviders.filter { $0.kind == .llm }

    Form {
      Section {
        Picker("Engine", selection: $settings.selectionBarSearchEngine) {
          Text("Google").tag(SelectionBarSearchEngine.google)
          Text("Baidu").tag(SelectionBarSearchEngine.baidu)
          Text("Sogou").tag(SelectionBarSearchEngine.sogou)
          Text("360 Search").tag(SelectionBarSearchEngine.so360)
          Text("Bing").tag(SelectionBarSearchEngine.bing)
          Text("Yandex").tag(SelectionBarSearchEngine.yandex)
          Text("DuckDuckGo").tag(SelectionBarSearchEngine.duckDuckGo)
          Text("Custom").tag(SelectionBarSearchEngine.custom)
        }

        if settings.selectionBarSearchEngine == .custom {
          TextField("Custom Search", text: $settings.selectionBarSearchCustomScheme)
            .textFieldStyle(.roundedBorder)

          Text("Enter a URL scheme (e.g. myapp) or a full URL with {{query}}.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        Label("Web Search", systemImage: "magnifyingglass")
      }

      Section {
        let terminalApps = settings.availableSelectionBarTerminalApps()

        if terminalApps.isEmpty {
          Text("No supported terminal apps detected")
            .foregroundStyle(.secondary)
        } else {
          Picker("Terminal", selection: $settings.selectionBarTerminalApp) {
            ForEach(terminalApps, id: \.self) { terminalApp in
              Text(terminalApp.displayName).tag(terminalApp)
            }
          }
        }
      } header: {
        Label("Run Command", systemImage: "play.circle")
      } footer: {
        Text("Runs the selected command in the chosen terminal when the executable exists.")
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
        Label("Word Lookup", systemImage: "character.book.closed")
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
        Text(
          "Translate supports app providers and LLM providers. Target applies to LLM providers.")
      }

      builtInKeyBindingsSection(settings: settings)

      Section {
        Toggle("Enable Speak", isOn: $settings.selectionBarSpeakEnabled)

        if settings.selectionBarSpeakEnabled {
          let speakProviders = settings.availableSelectionBarSpeakProviders()
          let systemSpeakProviders = speakProviders.filter { $0.kind == .system }
          let apiSpeakProviders = speakProviders.filter { $0.kind == .api }
          let customSpeakProviders = speakProviders.filter { $0.kind == .custom }

          Picker("Provider", selection: $settings.selectionBarSpeakProviderId) {
            ForEach(systemSpeakProviders, id: \.id) { provider in
              Text(provider.name).tag(provider.id)
            }
            if !systemSpeakProviders.isEmpty && !apiSpeakProviders.isEmpty {
              Divider()
            }
            ForEach(apiSpeakProviders, id: \.id) { provider in
              Text(provider.name).tag(provider.id)
            }
            if !apiSpeakProviders.isEmpty && !customSpeakProviders.isEmpty
              || !systemSpeakProviders.isEmpty && !customSpeakProviders.isEmpty
            {
              Divider()
            }
            ForEach(customSpeakProviders, id: \.id) { provider in
              Text(provider.name).tag(provider.id)
            }
          }

          if settings.isSelectionBarSystemSpeakProvider(
            id: settings.selectionBarSpeakProviderId
          ) {
            Picker("Voice", selection: $settings.selectionBarSpeakVoiceIdentifier) {
              Text("System Default").tag("")
              Divider()
              ForEach(SelectionBarSpeakService.availableSystemVoices()) { voice in
                Text(voice.displayName).tag(voice.identifier)
              }
            }
          } else if SelectionBarSpeakAPIProvider(rawValue: settings.selectionBarSpeakProviderId)
            == .elevenLabs
          {
            if settings.availableElevenLabsVoices.isEmpty {
              Text("No voices available. Save your API key and test the connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Picker("Voice", selection: $settings.elevenLabsVoiceId) {
                ForEach(settings.availableElevenLabsVoices) { voice in
                  Text(voice.name).tag(voice.voiceId)
                }
              }
            }
          }
        }
      } header: {
        Label("Speak", systemImage: "speaker.wave.2")
      } footer: {
        Text("Reads selected text aloud using the chosen provider and voice.")
      }

      Section {
        Toggle("Enable Chat", isOn: $settings.selectionBarChatEnabled)

        if settings.selectionBarChatEnabled {
          let chatProviders = settings.availableChatProviders()
          if chatProviders.isEmpty {
            Text("No LLM providers configured. Add an API key in Providers.")
              .foregroundStyle(.secondary)
              .font(.caption)
          } else {
            Picker("Provider", selection: $settings.selectionBarChatProviderId) {
              ForEach(chatProviders, id: \.id) { provider in
                Text(provider.name).tag(provider.id)
              }
            }
            .onChange(of: settings.selectionBarChatProviderId) { _, _ in
              settings.selectionBarChatModelId = ""
            }

            let chatModels = chatModelsForSelectedProvider(settings: settings)
            if chatModels.isEmpty {
              TextField("Model", text: $settings.selectionBarChatModelId)
                .textFieldStyle(.roundedBorder)
            } else {
              Picker("Model", selection: $settings.selectionBarChatModelId) {
                ForEach(chatModels, id: \.self) { model in
                  Text(model).tag(model)
                }
              }
            }
          }
        }
      } header: {
        Label("Chat", systemImage: "ellipsis.message")
      } footer: {
        Text("Chat with AI about selected text using streaming responses.")
      }

      ChatSessionsSettingsSection(settingsStore: settings)
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      settings.ensureValidSelectionBarTranslationProvider()
      settings.ensureValidSelectionBarTerminalApp()
      settings.ensureValidSelectionBarSpeakProvider()
      settings.reconcileActionsAvailabilityIfNeeded()
    }
    .onChange(of: settings.customLLMProviders) { _, _ in
      settings.ensureValidSelectionBarTranslationProvider()
      settings.ensureValidSelectionBarSpeakProvider()
    }
    .onChange(of: settings.availableOpenAIModels) { _, _ in
      settings.ensureValidSelectionBarTranslationProvider()
    }
    .onChange(of: settings.availableOpenRouterModels) { _, _ in
      settings.ensureValidSelectionBarTranslationProvider()
    }
  }

  @ViewBuilder
  private func builtInKeyBindingsSection(settings: SelectionBarSettingsStore) -> some View {
    Section {
      ActionsActionListContent(
        settingsStore: settings,
        actions: \.builtInKeyBindingActions,
        destination: .builtInKeyBindingActions,
        mode: .builtInKeyBinding,
        emptyMessage: "No key bindings configured",
        listMinHeight: 120,
        showsEnablementIssue: false,
        addMenuTitle: "Add Key Binding",
        editingAction: $editingAction
      ) {
        Button {
          editingAction = ActionsEditorItem(
            destination: .builtInKeyBindingActions,
            mode: .builtInKeyBinding,
            config: .newAction(kind: .keyBinding, isBuiltIn: true)
          )
        } label: {
          Label("Key Binding", systemImage: "keyboard")
        }

        Divider()

        ForEach(keyBindingTemplates) { template in
          Button {
            editingAction = ActionsEditorItem(
              destination: .builtInKeyBindingActions,
              mode: .builtInKeyBinding,
              config: .from(template: template, kind: .keyBinding, isBuiltIn: true)
            )
          } label: {
            HStack(spacing: 8) {
              ActionIconGlyph(icon: template.effectiveIcon, tint: .primary, size: 13)
              Text(template.localizedName)
            }
          }
        }
      }
    } header: {
      Label("Key Bindings", systemImage: "keyboard")
    } footer: {
      Text("Enabled key bindings appear before custom actions in Selection Bar.")
    }
  }

  private func chatModelsForSelectedProvider(
    settings: SelectionBarSettingsStore
  ) -> [String] {
    let providerId = settings.selectionBarChatProviderId
    switch providerId {
    case "openai":
      return settings.availableOpenAIModels.isEmpty
        ? [settings.openAIModel]
        : settings.availableOpenAIModels
    case "openrouter":
      return settings.availableOpenRouterModels.isEmpty
        ? [settings.openRouterModel]
        : settings.availableOpenRouterModels
    default:
      if let custom = settings.customLLMProviders.first(where: {
        $0.providerId == providerId
      }) {
        if !custom.models.isEmpty {
          return custom.models
        }
        if !custom.llmModel.isEmpty {
          return [custom.llmModel]
        }
      }
      return []
    }
  }
}

private struct ActionsCustomSettingsContent: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  @Binding var editingAction: ActionsEditorItem?
  let llmTemplates: [CustomActionConfig]
  let javaScriptTemplates: [CustomActionConfig]

  var body: some View {
    Form {
      Section {
        ActionsActionListContent(
          settingsStore: settingsStore,
          actions: \.customActions,
          destination: .customActions,
          mode: .custom,
          emptyMessage: "No actions configured",
          listMinHeight: 180,
          showsEnablementIssue: true,
          addMenuTitle: "Add Action",
          editingAction: $editingAction
        ) {
          Button {
            editingAction = ActionsEditorItem(
              destination: .customActions,
              mode: .custom,
              config: .newAction(kind: .javascript)
            )
          } label: {
            Label("Custom", systemImage: "square.and.pencil")
          }

          Button {
            editingAction = ActionsEditorItem(
              destination: .customActions,
              mode: .custom,
              config: .newAction(kind: .pipeline)
            )
          } label: {
            Label("Pipeline", systemImage: "app.connected.to.app.below.fill")
          }

          Divider()

          ForEach(javaScriptTemplates) { template in
            Button {
              editingAction = ActionsEditorItem(
                destination: .customActions,
                mode: .custom,
                config: .from(template: template, kind: .javascript)
              )
            } label: {
              HStack(spacing: 8) {
                ActionIconGlyph(icon: template.effectiveIcon, tint: .primary, size: 13)
                Text(template.localizedName)
              }
            }
          }

          Divider()

          ForEach(llmTemplates) { template in
            Button {
              editingAction = ActionsEditorItem(
                destination: .customActions,
                mode: .custom,
                config: .from(template: template, kind: .llm)
              )
            } label: {
              HStack(spacing: 8) {
                ActionIconGlyph(icon: template.effectiveIcon, tint: .primary, size: 13)
                Text(template.localizedName)
              }
            }
          }
        }
      } footer: {
        Text(
          "Enabled actions appear in Selection Bar actions. Drag to reorder enabled actions."
        )
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      settingsStore.reconcileActionsAvailabilityIfNeeded()
    }
  }
}

private struct ActionsProfilesSettingsContent: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  @Binding var editingProfile: ActionProfileEditorItem?

  var body: some View {
    Form {
      Section {
        if settingsStore.actionProfiles.isEmpty {
          Text("No profiles configured")
            .foregroundStyle(.secondary)
        } else {
          List {
            ForEach(settingsStore.actionProfiles) { profile in
              let status = settingsStore.actionProfileStatus(profile)
              ActionProfileListRow(
                profile: profile,
                status: status,
                onEdit: {
                  editingProfile = ActionProfileEditorItem(profile: profile)
                },
                onDelete: {
                  settingsStore.actionProfiles.removeAll { $0.id == profile.id }
                },
                onToggle: { isEnabled in
                  if let index = settingsStore.actionProfiles.firstIndex(where: {
                    $0.id == profile.id
                  }) {
                    settingsStore.actionProfiles[index].isEnabled = isEnabled
                  }
                }
              )
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 180)
        }

        Button {
          let profile = SelectionBarActionProfile(
            app: IgnoredApp(id: "", name: ""),
            isEnabled: true,
            actionIDs: settingsStore.orderedEnabledSelectionBarActions.map(\.id)
          )
          editingProfile = ActionProfileEditorItem(profile: profile)
        } label: {
          Label("Add Profile", systemImage: "plus.circle")
        }
      } footer: {
        Text("A matching enabled profile replaces the global action list for that app.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

private struct ActionProfileListRow: View {
  let profile: SelectionBarActionProfile
  let status: SelectionBarActionProfileStatus
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onToggle: (Bool) -> Void

  @State private var isEnabled: Bool

  init(
    profile: SelectionBarActionProfile,
    status: SelectionBarActionProfileStatus,
    onEdit: @escaping () -> Void,
    onDelete: @escaping () -> Void,
    onToggle: @escaping (Bool) -> Void
  ) {
    self.profile = profile
    self.status = status
    self.onEdit = onEdit
    self.onDelete = onDelete
    self.onToggle = onToggle
    self._isEnabled = State(initialValue: profile.isEnabled)
  }

  private var subtitle: String {
    let actionFormat = String(localized: "%d actions")
    var parts = [String(format: actionFormat, status.validActionCount)]
    if status.missingActionCount > 0 {
      let missingFormat = String(localized: "%d missing")
      parts.append(String(format: missingFormat, status.missingActionCount))
    }
    if status.invalidActionCount > 0 {
      let invalidFormat = String(localized: "%d invalid")
      parts.append(String(format: invalidFormat, status.invalidActionCount))
    }
    return parts.joined(separator: " • ")
  }

  var body: some View {
    HStack(spacing: 10) {
      ActionProfileAppIconView(bundleID: profile.app.id, size: 22)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(profile.app.name.isEmpty ? profile.app.id : profile.app.name)
          .lineLimit(1)
        Text(profile.app.id)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(status.hasIssues ? Color.red : Color.secondary)
      }

      Spacer()

      Toggle("", isOn: $isEnabled)
        .labelsHidden()
        .onChange(of: isEnabled) { _, newValue in
          onToggle(newValue)
        }

      Button("Edit", action: onEdit)

      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "Delete"))
    }
    .padding(.vertical, 4)
    .onChange(of: profile.isEnabled) { _, newValue in
      isEnabled = newValue
    }
  }
}

private struct ActionProfileEditorView: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  let profile: SelectionBarActionProfile
  let onSave: (SelectionBarActionProfile) -> Void
  let onCancel: () -> Void

  @State private var app: IgnoredApp
  @State private var isEnabled: Bool
  @State private var actionIDs: [UUID]
  @State private var showingAppPicker = false

  init(
    settingsStore: SelectionBarSettingsStore,
    profile: SelectionBarActionProfile,
    onSave: @escaping (SelectionBarActionProfile) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.settingsStore = settingsStore
    self.profile = profile
    self.onSave = onSave
    self.onCancel = onCancel
    self._app = State(initialValue: profile.app)
    self._isEnabled = State(initialValue: profile.isEnabled)
    self._actionIDs = State(initialValue: profile.actionIDs)
  }

  private var availableActions: [CustomActionConfig] {
    settingsStore.actionProfileAvailableActions
  }

  private var addableActions: [CustomActionConfig] {
    availableActions.filter { action in
      !actionIDs.contains(action.id)
    }
  }

  private var duplicateAppProfileExists: Bool {
    let appID = app.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !appID.isEmpty else { return false }
    return settingsStore.actionProfiles.contains { existing in
      existing.id != profile.id && existing.app.id == appID
    }
  }

  private var canSave: Bool {
    !app.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !duplicateAppProfileExists
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.escape)

        Spacer()

        Text(profile.app.id.isEmpty ? "New Profile" : "Edit Profile")
          .font(.headline)

        Spacer()

        Button("Save") {
          onSave(
            SelectionBarActionProfile(
              id: profile.id,
              app: app,
              isEnabled: isEnabled,
              actionIDs: actionIDs
            ))
        }
        .keyboardShortcut(.return)
        .disabled(!canSave)
      }
      .padding()

      Divider()

      Form {
        Section {
          HStack(spacing: 10) {
            ActionProfileAppIconView(bundleID: app.id, size: 28)
              .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
              Text(app.name.isEmpty ? "No application selected" : app.name)
              if !app.id.isEmpty {
                Text(app.id)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }

            Spacer()

            Button(app.id.isEmpty ? "Choose App" : "Change App") {
              showingAppPicker = true
            }
          }

          if duplicateAppProfileExists {
            Text("A profile already exists for this application.")
              .font(.caption)
              .foregroundStyle(.red)
          }

          Toggle("Enable Profile", isOn: $isEnabled)
        } header: {
          Label("Application", systemImage: "macwindow")
        }

        Section {
          if actionIDs.isEmpty {
            Text("No actions configured")
              .foregroundStyle(.secondary)
          } else {
            ForEach(Array(actionIDs.enumerated()), id: \.element) { index, actionID in
              profileActionRow(actionID: actionID, index: index)
            }
          }

          Menu {
            ForEach(addableActions) { action in
              Button {
                actionIDs.append(action.id)
              } label: {
                Label(action.localizedName, systemImage: action.effectiveIcon.resolvedValue)
              }
            }
          } label: {
            Label("Add Action", systemImage: "plus.circle")
          }
          .disabled(addableActions.isEmpty)
        } header: {
          Label("Actions", systemImage: "list.number")
        } footer: {
          Text("These actions replace the global configured action list for the selected app.")
        }
      }
      .formStyle(.grouped)
      .padding()
    }
    .frame(width: 560, height: 560)
    .sheet(isPresented: $showingAppPicker) {
      ApplicationPickerSheet(
        existingBundleIDs: existingProfileBundleIDs(),
        selectionLimit: 1,
        onAppsSelected: { apps in
          guard let selected = apps.first else { return }
          app = selected
        }
      )
    }
  }

  @ViewBuilder
  private func profileActionRow(actionID: UUID, index: Int) -> some View {
    let action = availableActions.first { $0.id == actionID }
    let issue = action.flatMap { settingsStore.customActionEnablementIssue($0) }

    HStack(spacing: 8) {
      Text("\(index + 1).")
        .foregroundStyle(.secondary)
        .frame(width: 24, alignment: .trailing)

      if let action {
        ActionIconGlyph(icon: action.effectiveIcon, tint: .primary, size: 13)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 1) {
          Text(action.localizedName)
            .lineLimit(1)
          Text(actionSubtitle(action: action, issue: issue))
            .font(.caption)
            .foregroundStyle(issue == nil ? Color.secondary : Color.red)
        }
      } else {
        Image(systemName: "questionmark.circle")
          .foregroundStyle(.red)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 1) {
          Text("Missing Action")
          Text(actionID.uuidString)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(1)
        }
      }

      Spacer()

      Button {
        moveProfileAction(from: index, to: index - 1)
      } label: {
        Image(systemName: "chevron.up")
      }
      .buttonStyle(.borderless)
      .disabled(index == 0)
      .help(String(localized: "Move Up"))

      Button {
        moveProfileAction(from: index, to: index + 1)
      } label: {
        Image(systemName: "chevron.down")
      }
      .buttonStyle(.borderless)
      .disabled(index >= actionIDs.count - 1)
      .help(String(localized: "Move Down"))

      Button(role: .destructive) {
        actionIDs.removeAll { $0 == actionID }
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "Remove"))
    }
  }

  private func actionSubtitle(
    action: CustomActionConfig,
    issue: CustomActionEnablementIssue?
  ) -> String {
    guard issue == nil else {
      return String(localized: "Invalid action")
    }

    switch action.kind {
    case .keyBinding:
      if let shortcut = SelectionBarKeyboardShortcutParser.parse(action.keyBinding) {
        return String(format: String(localized: "Key Binding • %@"), shortcut.displayString)
      }
      return String(localized: "Key Binding")
    case .javascript:
      return String(localized: "JavaScript")
    case .llm:
      return String(localized: "LLM")
    case .pipeline:
      return String(format: String(localized: "Pipeline • %d steps"), action.pipelineSteps.count)
    }
  }

  private func moveProfileAction(from source: Int, to destination: Int) {
    guard actionIDs.indices.contains(source), actionIDs.indices.contains(destination) else {
      return
    }
    actionIDs.swapAt(source, destination)
  }

  private func existingProfileBundleIDs() -> Set<String> {
    Set(
      settingsStore.actionProfiles.compactMap { existing in
        existing.id == profile.id ? nil : existing.app.id
      })
  }
}

/// Shared action list body: empty state, reorderable rows, and the "add" menu.
///
/// The built-in key binding list and the custom action list differ only in which array of
/// `CustomActionConfig` they operate on, the editor destination/mode they open, and the
/// contents of their add menu.
private struct ActionsActionListContent<AddMenuItems: View>: View {
  let settingsStore: SelectionBarSettingsStore
  let actions: ReferenceWritableKeyPath<SelectionBarSettingsStore, [CustomActionConfig]>
  let destination: ActionEditorDestination
  let mode: ActionEditorMode
  let emptyMessage: LocalizedStringKey
  let listMinHeight: CGFloat
  let showsEnablementIssue: Bool
  let addMenuTitle: LocalizedStringKey
  @Binding var editingAction: ActionsEditorItem?
  @ViewBuilder let addMenuItems: AddMenuItems

  private var configs: [CustomActionConfig] {
    settingsStore[keyPath: actions]
  }

  private func editorItem(for config: CustomActionConfig) -> ActionsEditorItem {
    ActionsEditorItem(destination: destination, mode: mode, config: config)
  }

  var body: some View {
    if configs.isEmpty {
      Text(emptyMessage)
        .foregroundStyle(.secondary)
    } else {
      List {
        ForEach(configs) { config in
          let canEnable = settingsStore.canEnableCustomAction(config)
          let enablementIssue =
            showsEnablementIssue ? settingsStore.customActionEnablementIssue(config) : nil
          ActionsActionListRow(
            config: config,
            canEnable: canEnable,
            enablementIssue: enablementIssue,
            onEdit: {
              editingAction = editorItem(for: config)
            },
            onDelete: {
              settingsStore[keyPath: actions].removeAll { $0.id == config.id }
            },
            onToggle: { enabled in
              if let index = settingsStore[keyPath: actions].firstIndex(where: {
                $0.id == config.id
              }) {
                if enabled
                  && !settingsStore.canEnableCustomAction(settingsStore[keyPath: actions][index])
                {
                  editingAction = editorItem(for: settingsStore[keyPath: actions][index])
                  return
                }
                settingsStore[keyPath: actions][index].isEnabled = enabled
              }
            }
          )
        }
        .onMove { indices, newOffset in
          settingsStore[keyPath: actions].move(fromOffsets: indices, toOffset: newOffset)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .frame(minHeight: listMinHeight)
    }

    Menu {
      addMenuItems
    } label: {
      Label(addMenuTitle, systemImage: "plus.circle")
    }
  }
}

private struct ActionsActionListRow: View {
  let config: CustomActionConfig
  let canEnable: Bool
  let enablementIssue: CustomActionEnablementIssue?
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onToggle: (Bool) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.tertiary)

      ActionsActionRow(
        config: config,
        canEnable: canEnable,
        enablementIssue: enablementIssue,
        onEdit: onEdit,
        onDelete: onDelete,
        onToggle: onToggle
      )
    }
    .padding(.vertical, 4)
  }
}

private struct ChatSessionsSettingsSection: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  @State private var sessions: [ChatSessionRecord] = []
  @State private var showClearConfirmation = false
  @State private var store = ChatSessionStore()

  var body: some View {
    Section {
      Picker("Session Limit", selection: $settingsStore.selectionBarChatSessionLimit) {
        Text("20").tag(20)
        Text("50").tag(50)
        Text("100").tag(100)
      }

      if sessions.isEmpty {
        Text("No saved sessions")
          .foregroundStyle(.secondary)
          .font(.caption)
      } else {
        ForEach(sessions) { session in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(URL(fileURLWithPath: session.filePath).lastPathComponent)
                .font(.callout)
              Text(session.filePath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
              Text(
                String(
                  format: String(localized: "%d messages \u{00B7} %@"),
                  session.messages.count,
                  session.lastAccessedAt.formatted(.relative(presentation: .named))
                )
              )
              .font(.caption2)
              .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              store.deleteSession(forFilePath: session.filePath, sessionID: session.id)
              sessions = store.listSessions()
            } label: {
              Image(systemName: "trash")
                .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
          }
        }
      }

      if !sessions.isEmpty {
        Button("Clear All Sessions") {
          showClearConfirmation = true
        }
        .foregroundStyle(.red)
        .confirmationDialog("Clear All Sessions?", isPresented: $showClearConfirmation) {
          Button("Clear All", role: .destructive) {
            store.clearAll()
            sessions = store.listSessions()
          }
        }
      }
    } header: {
      Label("Chat Sessions", systemImage: "clock.arrow.circlepath")
    }
    .onAppear {
      sessions = store.listSessions()
    }
  }
}

private struct ActionsActionRow: View {
  let config: CustomActionConfig
  let canEnable: Bool
  let enablementIssue: CustomActionEnablementIssue?
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onToggle: (Bool) -> Void

  /// Mirrors the store rather than shadowing it in `@State`: the parents reject
  /// some enable attempts (opening the editor instead of writing the setting),
  /// and a local copy would stay stuck ON — leaving the row's Edit and Delete
  /// buttons permanently disabled.
  private var isEnabled: Bool { config.isEnabled }

  private var isEnabledBinding: Binding<Bool> {
    Binding(get: { config.isEnabled }, set: { onToggle($0) })
  }

  private var subtitleTone: Color {
    if config.kind == .llm, !isEnabled, enablementIssue != nil {
      return .red
    }
    if config.kind == .keyBinding,
      SelectionBarKeyboardShortcutParser.parse(config.keyBinding) == nil
    {
      return .red
    }
    return .secondary
  }

  private var subtitleText: String {
    switch config.kind {
    case .llm:
      if let enablementIssue, !isEnabled {
        switch enablementIssue {
        case .missingProvider:
          return String(localized: "Choose provider before enabling")
        case .missingModel:
          return String(localized: "Choose model before enabling")
        case .providerUnavailable:
          return String(localized: "Provider key missing")
        case .emptyPipeline, .missingPipelineStep, .invalidPipelineStep:
          return String(localized: "Invalid action")
        }
      }
      return config.modelId
    case .javascript:
      switch config.outputMode {
      case .inplace:
        return String(localized: "JavaScript • Inplace Edit")
      case .resultWindow:
        return String(localized: "JavaScript • Result Window")
      }
    case .keyBinding:
      if let shortcut = SelectionBarKeyboardShortcutParser.parse(config.keyBinding) {
        let format = String(localized: "Key Binding • %@")
        return String(format: format, shortcut.displayString)
      }
      return String(localized: "Key Binding • Invalid Shortcut")
    case .pipeline:
      if let enablementIssue {
        switch enablementIssue {
        case .emptyPipeline:
          return String(localized: "Pipeline needs at least one step")
        case .missingPipelineStep:
          return String(localized: "Pipeline has a missing step")
        case .invalidPipelineStep:
          return String(localized: "Pipeline has an invalid step")
        case .missingProvider, .missingModel, .providerUnavailable:
          return String(localized: "Pipeline has an invalid LLM step")
        }
      }
      let format = String(localized: "Pipeline • %d steps")
      return String(format: format, config.pipelineSteps.count)
    }
  }

  init(
    config: CustomActionConfig,
    canEnable: Bool,
    enablementIssue: CustomActionEnablementIssue?,
    onEdit: @escaping () -> Void,
    onDelete: @escaping () -> Void,
    onToggle: @escaping (Bool) -> Void
  ) {
    self.config = config
    self.canEnable = canEnable
    self.enablementIssue = enablementIssue
    self.onEdit = onEdit
    self.onDelete = onDelete
    self.onToggle = onToggle
  }

  var body: some View {
    HStack {
      HStack(spacing: 8) {
        ActionIconGlyph(
          icon: config.effectiveIcon,
          tint: isEnabled ? .blue : .secondary,
          size: 13
        )
        .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(config.localizedName)
            .font(.callout)

          Text(subtitleText)
            .font(.caption2)
            .foregroundStyle(subtitleTone)
        }
      }

      Spacer()

      Toggle(isOn: isEnabledBinding) {
        EmptyView()
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .labelsHidden()
      .disabled(!canEnable && !isEnabled)
      .accessibilityLabel(
        Text(String(format: String(localized: "Enable %@"), config.localizedName))
      )

      Button(action: onEdit) {
        Image(systemName: "square.and.pencil")
          .foregroundStyle(.secondary)
          .font(.system(size: 17, weight: .medium))
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .disabled(isEnabled)
      .accessibilityLabel(
        Text(String(format: String(localized: "Edit %@"), config.localizedName))
      )

      Button(action: onDelete) {
        Image(systemName: "trash")
          .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
          .font(.system(size: 17, weight: .medium))
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .disabled(isEnabled)
      .accessibilityLabel(
        Text(String(format: String(localized: "Delete %@"), config.localizedName))
      )
    }
  }
}
