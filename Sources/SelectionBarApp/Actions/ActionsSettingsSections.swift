import SelectionBarCore
import SwiftUI

private enum ActionsTab: Hashable {
  case builtIn
  case custom
}

struct ActionsSettingsSections: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  @State private var selectedTab: ActionsTab? = .builtIn
  @State private var editingConfig: CustomActionConfig?

  private var llmTemplates: [CustomActionConfig] {
    CustomActionConfig.createAllBuiltInTemplates()
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
      }
      .frame(width: 180)
      .listStyle(.sidebar)

      Divider()

      Group {
        switch selectedTab {
        case .builtIn:
          ActionsBuiltInSettingsContent(settingsStore: settingsStore)
        case .custom:
          ActionsCustomSettingsContent(
            settingsStore: settingsStore,
            editingConfig: $editingConfig,
            llmTemplates: llmTemplates,
            javaScriptTemplates: javaScriptTemplates
          )
        case .none:
          ActionsBuiltInSettingsContent(settingsStore: settingsStore)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .sheet(item: $editingConfig) { config in
      ActionsCustomActionEditorView(
        settingsStore: settingsStore,
        config: config,
        onSave: { newConfig in
          if let existingIndex = settingsStore.customActions.firstIndex(where: {
            $0.id == newConfig.id
          }) {
            settingsStore.customActions[existingIndex] = newConfig
          } else {
            settingsStore.customActions.append(newConfig)
          }
          editingConfig = nil
        },
        onCancel: { editingConfig = nil }
      )
    }
  }
}

private struct ActionsBuiltInSettingsContent: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

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
        Text(
          "Translate supports app providers and LLM providers. Target applies to LLM providers.")
      }
    }
    .formStyle(.grouped)
    .padding()
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

private struct ActionsCustomSettingsContent: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  @Binding var editingConfig: CustomActionConfig?
  let llmTemplates: [CustomActionConfig]
  let javaScriptTemplates: [CustomActionConfig]

  var body: some View {
    Form {
      Section {
        if settingsStore.customActions.isEmpty {
          Text("No actions configured")
            .foregroundStyle(.secondary)
        } else {
          List {
            ForEach(settingsStore.customActions) { config in
              let canEnable = settingsStore.canEnableCustomAction(config)
              let enablementIssue = settingsStore.llmActionEnablementIssue(config)
              ActionsActionListRow(
                config: config,
                canEnable: canEnable,
                enablementIssue: enablementIssue,
                onEdit: { editingConfig = config },
                onDelete: {
                  settingsStore.customActions.removeAll { $0.id == config.id }
                },
                onToggle: { enabled in
                  if let index = settingsStore.customActions.firstIndex(where: {
                    $0.id == config.id
                  }) {
                    if enabled
                      && !settingsStore.canEnableCustomAction(settingsStore.customActions[index])
                    {
                      editingConfig = settingsStore.customActions[index]
                      return
                    }
                    settingsStore.customActions[index].isEnabled = enabled
                  }
                }
              )
            }
            .onMove { indices, newOffset in
              settingsStore.customActions.move(fromOffsets: indices, toOffset: newOffset)
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 180)
        }

        Menu {
          Button {
            editingConfig = CustomActionConfig(
              id: UUID(),
              name: "",
              prompt: CustomActionConfig.defaultPromptTemplate,
              modelProvider: "",
              modelId: "",
              kind: .javascript,
              outputMode: .resultWindow,
              script: CustomActionConfig.defaultJavaScriptTemplate,
              isEnabled: false,
              isBuiltIn: false,
              templateId: nil,
              icon: nil
            )
          } label: {
            Label("Custom", systemImage: "square.and.pencil")
          }

          Divider()

          ForEach(javaScriptTemplates) { template in
            Button {
              editingConfig = CustomActionConfig(
                id: UUID(),
                name: template.name,
                prompt: CustomActionConfig.defaultPromptTemplate,
                modelProvider: "",
                modelId: "",
                kind: .javascript,
                outputMode: template.outputMode,
                script: template.script,
                isEnabled: false,
                isBuiltIn: false,
                templateId: nil,
                icon: template.effectiveIcon
              )
            } label: {
              HStack(spacing: 8) {
                ActionIconGlyph(icon: template.effectiveIcon, tint: .primary, size: 13)
                Text(template.name)
              }
            }
          }

          Divider()

          ForEach(llmTemplates) { template in
            Button {
              editingConfig = CustomActionConfig(
                id: UUID(),
                name: template.name,
                prompt: template.prompt,
                modelProvider: template.modelProvider,
                modelId: template.modelId,
                kind: .llm,
                outputMode: .resultWindow,
                script: CustomActionConfig.defaultJavaScriptTemplate,
                isEnabled: false,
                isBuiltIn: false,
                templateId: nil,
                icon: template.effectiveIcon
              )
            } label: {
              HStack(spacing: 8) {
                ActionIconGlyph(icon: template.effectiveIcon, tint: .primary, size: 13)
                Text(template.localizedName)
              }
            }
          }
        } label: {
          Label("Add Action", systemImage: "plus.circle")
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
      settingsStore.reconcileCustomActionsAvailabilityIfNeeded()
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

private struct ActionsActionRow: View {
  let config: CustomActionConfig
  let canEnable: Bool
  let enablementIssue: CustomActionEnablementIssue?
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onToggle: (Bool) -> Void

  @State private var isEnabled: Bool

  private var subtitleTone: Color {
    if config.kind == .llm, !isEnabled, enablementIssue != nil {
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
    self._isEnabled = State(initialValue: config.isEnabled)
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

      Toggle(isOn: $isEnabled) {
        EmptyView()
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .labelsHidden()
      .disabled(!canEnable && !isEnabled)
      .onChange(of: isEnabled) { _, newValue in
        onToggle(newValue)
      }

      Button(action: onEdit) {
        Image(systemName: "square.and.pencil")
          .foregroundStyle(.secondary)
          .font(.system(size: 17, weight: .medium))
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .disabled(isEnabled)

      Button(action: onDelete) {
        Image(systemName: "trash")
          .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
          .font(.system(size: 17, weight: .medium))
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .disabled(isEnabled)
    }
    .onChange(of: config.isEnabled) { _, newValue in
      isEnabled = newValue
    }
  }
}
