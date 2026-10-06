import SelectionBarCore
import SwiftUI

struct GrammarSettingsTab: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  @Bindable var coordinator: GrammarCoordinator
  @State private var showAppPicker = false

  private var models: [String] {
    switch settingsStore.grammar.providerID {
    case "openai": settingsStore.availableOpenAIModels
    case "openrouter": settingsStore.availableOpenRouterModels
    default:
      settingsStore.customLLMProviders.first { $0.providerId == settingsStore.grammar.providerID }?
        .models ?? []
    }
  }

  var body: some View {
    Form {
      Section {
        Picker("Check grammar", selection: $settingsStore.grammar.mode) {
          ForEach(GrammarTriggerMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        if settingsStore.grammar.mode != .off {
          if !settingsStore.selectionBarEnabled {
            Text("Enable SelectionBar in General to run grammar checks.")
              .foregroundStyle(.secondary)
          }
          LabeledContent("Check shortcut") {
            ShortcutRecorderField(keyBinding: $settingsStore.grammar.shortcut, width: 240)
          }
          if settingsStore.grammar.shortcut.isEmpty {
            Text("Record a shortcut for manual checks.").foregroundStyle(.secondary)
          }
          if let error = coordinator.shortcutError { Text(error).foregroundStyle(.red) }
        }
      }
      if settingsStore.grammar.mode != .off {
        Section {
          Picker("Provider", selection: $settingsStore.grammar.providerID) {
            Text("Select provider").tag("")
            let providers = settingsStore.availableChatProviders()
            if !settingsStore.grammar.providerID.isEmpty,
              !providers.contains(where: { $0.id == settingsStore.grammar.providerID })
            {
              Text("Unavailable provider").tag(settingsStore.grammar.providerID)
            }
            ForEach(providers) { provider in Text(provider.name).tag(provider.id) }
          }
          .onChange(of: settingsStore.grammar.providerID) { _, _ in
            settingsStore.grammar.modelID = ""
          }
          Picker("Model", selection: $settingsStore.grammar.modelID) {
            Text("Use provider default").tag("")
            if !settingsStore.grammar.modelID.isEmpty,
              !models.contains(settingsStore.grammar.modelID)
            {
              Text(settingsStore.grammar.modelID).tag(settingsStore.grammar.modelID)
            }
            ForEach(models, id: \.self) { model in
              Text(model).tag(model)
            }
          }
          .pickerStyle(.menu)
          Picker("English convention", selection: $settingsStore.grammar.englishConvention) {
            ForEach(GrammarEnglishConvention.allCases, id: \.self) { convention in
              Text(convention.displayName).tag(convention)
            }
          }
          if let error = coordinator.automaticError { Text(error).foregroundStyle(.red) }
        } footer: {
          Text(
            "Checked text is sent to the selected provider. Languages are detected automatically.")
        }
        if settingsStore.grammar.mode == .automatic {
          Section("Skip automatic checking in") {
            ForEach(settingsStore.grammar.excludedApps) { app in
              HStack {
                Text(app.name)
                Spacer()
                Button("Remove", systemImage: "minus.circle.fill") {
                  settingsStore.grammar.excludedApps.removeAll { $0.id == app.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
              }
            }
            Button("Add Application", systemImage: "plus.circle") { showAppPicker = true }
          }
        }
      }
    }
    .formStyle(.grouped)
    .sheet(isPresented: $showAppPicker) {
      ApplicationPickerSheet(existingBundleIDs: Set(settingsStore.grammar.excludedApps.map(\.id))) {
        settingsStore.grammar.excludedApps.append(contentsOf: $0)
      }
    }
  }
}
