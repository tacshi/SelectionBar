import Foundation
import SelectionBarCore
import SwiftUI

private struct ActionProviderOption: Identifiable {
  let id: String
  let name: String
  let models: [String]
}

private enum ActionIconMode: String, CaseIterable, Identifiable {
  case automatic
  case sfSymbol

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: "Default"
    case .sfSymbol: "SF Symbol"
    }
  }
}

struct ActionIconGlyph: View {
  let icon: CustomActionIcon
  let tint: Color
  let size: CGFloat

  var body: some View {
    Image(systemName: icon.resolvedValue)
      .font(.system(size: size, weight: .medium))
      .foregroundStyle(tint)
      .frame(width: size + 2, height: size + 2)
  }
}

struct ActionsCustomActionEditorView: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  let config: CustomActionConfig
  let onSave: (CustomActionConfig) -> Void
  let onCancel: () -> Void

  @State private var name = ""
  @State private var prompt = ""
  @State private var modelProvider: String?
  @State private var modelId: String?
  @State private var actionKind: CustomActionKind = .javascript
  @State private var outputMode: CustomActionOutputMode = .resultWindow
  @State private var script = CustomActionConfig.defaultJavaScriptTemplate
  @State private var availableModels: [String] = []
  @State private var iconMode: ActionIconMode = .automatic
  @State private var selectedSFSymbol = "sparkles"
  @State private var showingSFSymbolPicker = false
  @State private var sfSymbolSearchText = ""

  private static let allSFSymbolNames: [String] = SFSymbolCatalog.names

  private var filteredSFSymbolNames: [String] {
    let query = sfSymbolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return Self.allSFSymbolNames }
    return Self.allSFSymbolNames.filter { $0.localizedStandardContains(query) }
  }

  private var isNewAction: Bool {
    config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var providerOptions: [ActionProviderOption] {
    var options: [ActionProviderOption] = []

    if settingsStore.openAIAPIKeyConfigured {
      options.append(
        ActionProviderOption(
          id: "openai",
          name: "OpenAI",
          models: normalizedModels(
            settingsStore.availableOpenAIModels,
            fallbackModel: settingsStore.openAIModel
          )
        )
      )
    }

    if settingsStore.openRouterAPIKeyConfigured {
      options.append(
        ActionProviderOption(
          id: "openrouter",
          name: "OpenRouter",
          models: normalizedModels(
            settingsStore.availableOpenRouterModels,
            fallbackModel: settingsStore.openRouterModel
          )
        )
      )
    }

    for provider in settingsStore.customLLMProviders where provider.capabilities.contains(.llm) {
      guard settingsStore.isCustomProviderAPIKeyConfigured(id: provider.id) else { continue }
      options.append(
        ActionProviderOption(
          id: provider.providerId,
          name: provider.name,
          models: normalizedModels(provider.models, fallbackModel: provider.llmModel)
        )
      )
    }

    return options
  }

  private var canSave: Bool {
    switch actionKind {
    case .llm:
      return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && modelProvider != nil
        && modelId != nil
    case .javascript:
      return !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.escape)

        Spacer()

        Text(isNewAction ? "New Action" : "Edit Action")
          .font(.headline)

        Spacer()

        Button("Save") {
          let newConfig = CustomActionConfig(
            id: config.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "Custom Action" : name,
            prompt: prompt,
            modelProvider: modelProvider ?? "",
            modelId: modelId ?? "",
            kind: actionKind,
            outputMode: outputMode,
            script: script,
            isEnabled: config.isEnabled,
            isBuiltIn: false,
            templateId: nil,
            icon: iconForSave()
          )
          onSave(newConfig)
        }
        .keyboardShortcut(.return)
        .disabled(!canSave)
      }
      .padding()

      Divider()

      List {
        Section {
          TextField("Action Name", text: $name)
            .textFieldStyle(.roundedBorder)
        }

        Section("Icon") {
          Picker("Style", selection: $iconMode) {
            ForEach(ActionIconMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }

          if iconMode == .sfSymbol {
            HStack(spacing: 8) {
              ActionIconGlyph(
                icon: CustomActionIcon(value: selectedSFSymbol),
                tint: .primary,
                size: 16
              )
              .frame(width: 20)

              TextField("SF Symbol Name", text: .constant(selectedSFSymbol))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

              Button("Pick SF Symbol") {
                showingSFSymbolPicker = true
              }
            }
            .listRowSeparator(.hidden, edges: .bottom)
          }
        }

        Section("Execution") {
          Picker("Kind", selection: $actionKind) {
            ForEach(CustomActionKind.allCases, id: \.self) { kind in
              Text(kind.displayName).tag(kind)
            }
          }

          Picker("Output", selection: $outputMode) {
            ForEach(CustomActionOutputMode.allCases, id: \.self) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
        }

        if actionKind == .llm {
          Section("Model") {
            Picker("Provider", selection: $modelProvider) {
              Text("Select").tag(Optional<String>.none)
              ForEach(providerOptions) { option in
                Text(option.name).tag(Optional(option.id))
              }
            }
            .disabled(providerOptions.isEmpty)
            .onChange(of: modelProvider) { _, _ in
              modelId = nil
              refreshAvailableModels()
            }

            if providerOptions.isEmpty {
              Text("No configured providers. Configure a provider in the Providers tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Picker("Model", selection: $modelId) {
              Text("Select").tag(Optional<String>.none)
              ForEach(availableModels, id: \.self) { model in
                Text(model).tag(Optional(model))
              }
            }
            .disabled(modelProvider == nil || availableModels.isEmpty)
          }

          Section {
            TextEditor(text: $prompt)
              .font(.system(.body, design: .monospaced))
              .frame(height: 180)
          } header: {
            Text("Prompt Template")
          } footer: {
            Text("Use {{TEXT}} as placeholder for the selected text.")
              .font(.caption)
          }
        } else {
          Section {
            TextEditor(text: $script)
              .font(.system(.body, design: .monospaced))
              .frame(height: 300)
          } header: {
            Text("JavaScript")
          } footer: {
            Text("Define a synchronous function transform(input) that returns a string.")
              .font(.caption)
          }

          Section {
            TextEditor(text: $prompt)
              .font(.system(.body, design: .monospaced))
              .frame(height: 120)
          } header: {
            Text("LLM Prompt (Optional, unused for JavaScript)")
          } footer: {
            Text("This is kept so switching back to LLM preserves your previous prompt.")
              .font(.caption)
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(width: 520, height: 560)
    .onAppear {
      settingsStore.refreshCredentialAvailability()
      name = config.name
      prompt = config.prompt
      actionKind = config.kind
      outputMode = config.outputMode
      script =
        config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? CustomActionConfig.defaultJavaScriptTemplate
        : config.script
      if config.kind == .llm {
        modelProvider = config.modelProvider.isEmpty ? nil : config.modelProvider
        modelId = config.modelId.isEmpty ? nil : config.modelId
      } else {
        modelProvider = config.modelProvider.isEmpty ? nil : config.modelProvider
        modelId = config.modelId.isEmpty ? nil : config.modelId
      }
      selectedSFSymbol = config.defaultIconSFSymbolName
      if let icon = config.icon {
        iconMode = .sfSymbol
        selectedSFSymbol = icon.value
      } else {
        iconMode = .automatic
      }
      refreshAvailableModels()
    }
    .onChange(of: actionKind) { _, newKind in
      switch newKind {
      case .llm:
        outputMode = .resultWindow
        refreshAvailableModels()
      case .javascript:
        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          script = CustomActionConfig.defaultJavaScriptTemplate
        }
      }
    }
    .sheet(isPresented: $showingSFSymbolPicker) {
      NavigationStack {
        List(filteredSFSymbolNames, id: \.self) { symbol in
          Button {
            selectedSFSymbol = symbol
            showingSFSymbolPicker = false
          } label: {
            HStack(spacing: 10) {
              Image(systemName: symbol)
                .frame(width: 20)
              Text(symbol)
                .font(.system(.body, design: .monospaced))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        }
        .navigationTitle("SF Symbols")
        .searchable(text: $sfSymbolSearchText, prompt: "Search symbols")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              showingSFSymbolPicker = false
            }
          }
        }
      }
      .frame(width: 520, height: 560)
    }
  }

  private func normalizedModels(_ models: [String], fallbackModel: String) -> [String] {
    var seen: Set<String> = []
    var normalized: [String] = []

    for model in models {
      let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      guard seen.insert(trimmed).inserted else { continue }
      normalized.append(trimmed)
    }

    let fallback = fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fallback.isEmpty && seen.insert(fallback).inserted {
      normalized.append(fallback)
    }

    return normalized
  }

  private func refreshAvailableModels() {
    guard actionKind == .llm else {
      return
    }

    guard let modelProvider else {
      availableModels = []
      modelId = nil
      return
    }

    guard let option = providerOptions.first(where: { $0.id == modelProvider }) else {
      availableModels = []
      modelId = nil
      return
    }

    availableModels = option.models

    if availableModels.isEmpty
      && !config.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && config.modelProvider == modelProvider
    {
      availableModels = [config.modelId]
    }

    if let modelId, !availableModels.contains(modelId) {
      availableModels.insert(modelId, at: 0)
    }

    if let currentModel = modelId, availableModels.contains(currentModel) {
      return
    }

    modelId = nil
  }

  private func iconForSave() -> CustomActionIcon? {
    switch iconMode {
    case .automatic:
      return nil
    case .sfSymbol:
      let value = selectedSFSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : CustomActionIcon(value: value)
    }
  }
}

private enum SFSymbolCatalog {
  static let names: [String] = {
    let paths = [
      "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist",
      "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist",
    ]

    for path in paths {
      guard let symbols = NSArray(contentsOfFile: path) as? [String], !symbols.isEmpty else {
        continue
      }
      return symbols
    }

    return [
      "sparkles",
      "wand.and.stars",
      "text.badge.checkmark",
      "eraser",
      "checklist",
      "list.bullet",
      "text.alignleft",
      "doc.text",
      "quote.bubble",
      "envelope",
      "lightbulb",
      "magnifyingglass",
      "bolt",
      "gearshape",
      "paperplane",
      "bookmark",
      "pencil",
    ]
  }()
}
