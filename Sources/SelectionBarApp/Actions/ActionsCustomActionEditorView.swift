import AppKit
import Carbon.HIToolbox
import Foundation
import SelectionBarCore
import SwiftUI

private struct ActionProviderOption: Identifiable {
  let id: String
  let name: String
  let models: [String]
}

enum ActionEditorMode: Hashable {
  case custom
  case builtInKeyBinding
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

  let mode: ActionEditorMode
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
  @State private var keyBinding = ""
  @State private var keyBindingOverrides: [CustomActionKeyBindingOverride] = []
  @State private var pipelineSteps: [CustomActionPipelineStep] = []
  @State private var availableModels: [String] = []
  @State private var selectedSFSymbol = "sparkles"
  @State private var includesSourceContext = false
  @State private var showingSFSymbolPicker = false
  @State private var showingOverrideAppPicker = false
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

  private var availableKinds: [CustomActionKind] {
    switch mode {
    case .custom:
      return [.javascript, .llm, .pipeline]
    case .builtInKeyBinding:
      return [.keyBinding]
    }
  }

  private var pipelineStepOptions: [CustomActionConfig] {
    settingsStore.customActions.filter { action in
      action.id != config.id && (action.kind == .javascript || action.kind == .llm)
    }
  }

  private var parsedKeyBinding: SelectionBarKeyboardShortcut? {
    SelectionBarKeyboardShortcutParser.parse(keyBinding)
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
    if mode == .builtInKeyBinding {
      let hasInvalidOverride = keyBindingOverrides.contains { !isValidKeyBindingOverride($0) }
      return parsedKeyBinding != nil && !hasInvalidOverride
    }

    switch actionKind {
    case .llm:
      return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && modelProvider != nil
        && modelId != nil
    case .javascript:
      return !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .pipeline:
      return !pipelineSteps.isEmpty
        && pipelineSteps.allSatisfy { step in
          pipelineStepOptions.contains { $0.id == step.actionID }
        }
    case .keyBinding:
      return false
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.escape)

        Spacer()

        Text(
          isNewAction
            ? String(localized: "New Action")
            : String(localized: "Edit Action")
        )
        .font(.headline)

        Spacer()

        Button("Save") {
          onSave(makeConfig())
        }
        .keyboardShortcut(.return)
        .disabled(!canSave)
      }
      .padding()

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ActionEditorSection {
            TextField("Action Name", text: $name)
              .textFieldStyle(.roundedBorder)
          }

          ActionEditorSection("Icon") {
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
          }

          if mode == .custom {
            ActionEditorSection("Execution") {
              ActionEditorRow("Kind") {
                Picker("", selection: $actionKind) {
                  ForEach(availableKinds, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                  }
                }
                .labelsHidden()
                .frame(width: 180)
              }

              ActionEditorRow("Output") {
                Picker("", selection: $outputMode) {
                  ForEach(CustomActionOutputMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                  }
                }
                .labelsHidden()
                .frame(width: 180)
              }
            }
          }

          if mode == .custom && actionKind == .llm {
            ActionEditorSection("Model") {
              ActionEditorRow("Provider") {
                Picker("", selection: $modelProvider) {
                  Text("Select").tag(Optional<String>.none)
                  ForEach(providerOptions) { option in
                    Text(option.name).tag(Optional(option.id))
                  }
                }
                .labelsHidden()
                .frame(width: 180)
                .disabled(providerOptions.isEmpty)
                .onChange(of: modelProvider) { _, _ in
                  modelId = nil
                  refreshAvailableModels()
                }
              }

              if providerOptions.isEmpty {
                Text("No configured providers. Configure a provider in the Providers tab.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              ActionEditorRow("Model") {
                Picker("", selection: $modelId) {
                  Text("Select").tag(Optional<String>.none)
                  ForEach(availableModels, id: \.self) { model in
                    Text(model).tag(Optional(model))
                  }
                }
                .labelsHidden()
                .frame(width: 180)
                .disabled(modelProvider == nil || availableModels.isEmpty)
              }
            }

            ActionEditorSection("Context") {
              Toggle("Include Source Context", isOn: $includesSourceContext)

              Text(
                "When enabled, this action reads a bounded excerpt around the selection from the current file, PDF, or web page."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }

            ActionEditorSection("Prompt Template") {
              TextEditor(text: $prompt)
                .font(.system(.body, design: .monospaced))
                .frame(height: 180)
                .actionEditorTextBox()

              Text(
                "Use {{TEXT}} for the selected text. Source context actions can also use {{CONTEXT}}, {{SOURCE_URL}}, {{APP_NAME}}, and {{BUNDLE_ID}}."
              )
              .font(.caption)
            }
          } else if mode == .custom && actionKind == .javascript {
            ActionEditorSection("JavaScript") {
              TextEditor(text: $script)
                .font(.system(.body, design: .monospaced))
                .frame(height: 300)
                .actionEditorTextBox()

              Text(
                "Define transform(input) to return a string or async Promise<string>. Use await fetch(...) for HTTP/HTTPS requests."
              )
              .font(.caption)
            }
          } else if mode == .custom && actionKind == .pipeline {
            ActionEditorSection("Pipeline") {
              if pipelineStepOptions.isEmpty {
                Text("Create a JavaScript or LLM action first.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else if pipelineSteps.isEmpty {
                Text("No steps configured")
                  .foregroundStyle(.secondary)
              } else {
                ForEach(Array(pipelineSteps.enumerated()), id: \.element.id) { index, step in
                  pipelineStepRow(step: step, index: index)
                }
              }

              Menu {
                ForEach(pipelineStepOptions) { option in
                  Button {
                    pipelineSteps.append(CustomActionPipelineStep(actionID: option.id))
                  } label: {
                    Label(option.localizedName, systemImage: option.effectiveIcon.resolvedValue)
                  }
                }
              } label: {
                Label("Add Step", systemImage: "plus.circle")
              }
              .disabled(pipelineStepOptions.isEmpty)
            }
          } else {
            ActionEditorSection("Shortcut") {
              ShortcutRecorderField(keyBinding: $keyBinding)

              if let parsedKeyBinding {
                let format = String(localized: "Will send: %@")
                Text(String(format: format, parsedKeyBinding.displayString))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else {
                let hasInput = !keyBinding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("Use format like cmd+b, cmd+shift+k, or ctrl+opt+return.")
                  .font(.caption)
                  .foregroundStyle(hasInput ? .red : .secondary)
              }

              Text("App Overrides")
                .font(.headline)
                .padding(.top, 6)

              if keyBindingOverrides.isEmpty {
                Text("No app overrides configured")
                  .foregroundStyle(.secondary)
              } else {
                ForEach($keyBindingOverrides) { $override in
                  VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                      KeyBindingOverrideAppIcon(bundleID: override.bundleID, size: 20)
                        .frame(width: 20, height: 20)

                      VStack(alignment: .leading, spacing: 1) {
                        let displayName = override.appName.trimmingCharacters(
                          in: .whitespacesAndNewlines)
                        Text(displayName.isEmpty ? override.bundleID : displayName)
                          .font(.callout)
                        Text(override.bundleID)
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      }

                      Spacer()

                      ShortcutRecorderField(
                        keyBinding: $override.keyBinding,
                        width: 190
                      )

                      Button(role: .destructive) {
                        keyBindingOverrides.removeAll { $0.bundleID == override.bundleID }
                      } label: {
                        Image(systemName: "trash")
                      }
                      .buttonStyle(.borderless)
                      .help(String(localized: "Remove"))
                    }

                    if let parsed = SelectionBarKeyboardShortcutParser.parse(override.keyBinding) {
                      let format = String(localized: "Will send: %@")
                      Text(String(format: format, parsed.displayString))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                      let hasInput =
                        !override.keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                      Text("Use format like cmd+b, cmd+shift+k, or ctrl+opt+return.")
                        .font(.caption)
                        .foregroundStyle(hasInput ? .red : .secondary)
                    }
                  }
                  .padding(.vertical, 2)
                }
              }

              Button {
                showingOverrideAppPicker = true
              } label: {
                Label("Add App Override", systemImage: "plus.circle")
              }

              Text("Use per-app shortcuts when apps require different bindings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
      }
    }
    .frame(width: 520, height: 560)
    .onAppear {
      settingsStore.refreshCredentialAvailability()
      name = config.name
      keyBinding = config.keyBinding
      keyBindingOverrides = config.keyBindingOverrides
      pipelineSteps = config.pipelineSteps

      if mode == .builtInKeyBinding {
        prompt = CustomActionConfig.defaultPromptTemplate
        actionKind = .keyBinding
        outputMode = .resultWindow
        script = CustomActionConfig.defaultJavaScriptTemplate
        modelProvider = nil
        modelId = nil
        includesSourceContext = false
        pipelineSteps = []
      } else {
        prompt = config.prompt
        actionKind = availableKinds.contains(config.kind) ? config.kind : .javascript
        outputMode = config.outputMode
        script =
          config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? CustomActionConfig.defaultJavaScriptTemplate
          : config.script
        modelProvider = config.modelProvider.isEmpty ? nil : config.modelProvider
        modelId = config.modelId.isEmpty ? nil : config.modelId
        includesSourceContext = config.kind == .llm && config.includesSourceContext
        pipelineSteps = config.kind == .pipeline ? config.pipelineSteps : []
      }

      selectedSFSymbol = config.defaultIconSFSymbolName
      if let icon = config.icon {
        selectedSFSymbol = icon.value
      }
      refreshAvailableModels()
    }
    .onChange(of: actionKind) { _, newKind in
      guard mode == .custom else { return }
      switch newKind {
      case .llm:
        outputMode = .resultWindow
        refreshAvailableModels()
      case .javascript:
        includesSourceContext = false
        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          script = CustomActionConfig.defaultJavaScriptTemplate
        }
      case .pipeline:
        includesSourceContext = false
        modelProvider = nil
        modelId = nil
      case .keyBinding:
        outputMode = .resultWindow
        includesSourceContext = false
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
    .sheet(isPresented: $showingOverrideAppPicker) {
      KeyBindingOverrideAppPickerSheet(
        existingBundleIDs: Set(keyBindingOverrides.map(\.bundleID)),
        onSelect: { app in
          keyBindingOverrides.append(
            CustomActionKeyBindingOverride(
              bundleID: app.bundleID,
              appName: app.name,
              keyBinding: keyBinding
            )
          )
        }
      )
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

  private func isValidKeyBindingOverride(_ override: CustomActionKeyBindingOverride) -> Bool {
    let bundleID = override.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    let keyBinding = override.keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
    return !bundleID.isEmpty && SelectionBarKeyboardShortcutParser.parse(keyBinding) != nil
  }

  @ViewBuilder
  private func pipelineStepRow(step: CustomActionPipelineStep, index: Int) -> some View {
    HStack(spacing: 8) {
      Text("\(index + 1).")
        .foregroundStyle(.secondary)
        .frame(width: 24, alignment: .trailing)

      Picker("", selection: pipelineStepActionBinding(for: step.id)) {
        if pipelineStepOptions.first(where: { $0.id == step.actionID }) == nil {
          Text("Missing Action").tag(step.actionID)
        }
        ForEach(pipelineStepOptions) { action in
          Text(action.localizedName).tag(action.id)
        }
      }
      .labelsHidden()

      if let selectedAction = pipelineStepOptions.first(where: { $0.id == step.actionID }) {
        Text(selectedAction.kind.displayName)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("Missing")
          .font(.caption)
          .foregroundStyle(.red)
      }

      Button {
        movePipelineStep(from: index, to: index - 1)
      } label: {
        Image(systemName: "chevron.up")
      }
      .buttonStyle(.borderless)
      .disabled(index == 0)
      .help(String(localized: "Move Up"))

      Button {
        movePipelineStep(from: index, to: index + 1)
      } label: {
        Image(systemName: "chevron.down")
      }
      .buttonStyle(.borderless)
      .disabled(index >= pipelineSteps.count - 1)
      .help(String(localized: "Move Down"))

      Button(role: .destructive) {
        pipelineSteps.removeAll { $0.id == step.id }
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "Remove"))
    }
  }

  private func pipelineStepActionBinding(for stepID: UUID) -> Binding<UUID> {
    Binding(
      get: {
        pipelineSteps.first(where: { $0.id == stepID })?.actionID ?? UUID()
      },
      set: { actionID in
        guard let index = pipelineSteps.firstIndex(where: { $0.id == stepID }) else { return }
        pipelineSteps[index].actionID = actionID
      }
    )
  }

  private func movePipelineStep(from source: Int, to destination: Int) {
    guard pipelineSteps.indices.contains(source), pipelineSteps.indices.contains(destination) else {
      return
    }
    pipelineSteps.swapAt(source, destination)
  }

  /// Derives the configuration represented by the editor's current form state.
  func makeConfig() -> CustomActionConfig {
    ActionEditorConfigInput(
      existingConfig: config,
      mode: mode,
      name: name,
      prompt: prompt,
      modelProvider: modelProvider,
      modelId: modelId,
      actionKind: actionKind,
      outputMode: outputMode,
      script: script,
      keyBinding: keyBinding,
      keyBindingOverrides: keyBindingOverrides,
      pipelineSteps: pipelineSteps,
      includesSourceContext: includesSourceContext,
      selectedSFSymbol: selectedSFSymbol
    ).makeConfig()
  }
}

/// Pure snapshot of the action editor's form state, used to derive a `CustomActionConfig`.
struct ActionEditorConfigInput {
  var existingConfig: CustomActionConfig = CustomActionConfig()
  var mode: ActionEditorMode = .custom
  var name: String = ""
  var prompt: String = ""
  var modelProvider: String?
  var modelId: String?
  var actionKind: CustomActionKind = .javascript
  var outputMode: CustomActionOutputMode = .resultWindow
  var script: String = CustomActionConfig.defaultJavaScriptTemplate
  var keyBinding: String = ""
  var keyBindingOverrides: [CustomActionKeyBindingOverride] = []
  var pipelineSteps: [CustomActionPipelineStep] = []
  var includesSourceContext: Bool = false
  var selectedSFSymbol: String = "sparkles"

  func makeConfig() -> CustomActionConfig {
    let resolvedKind: CustomActionKind = mode == .builtInKeyBinding ? .keyBinding : actionKind
    let resolvedPrompt =
      mode == .builtInKeyBinding || resolvedKind == .pipeline
      ? CustomActionConfig.defaultPromptTemplate : prompt
    let resolvedModelProvider =
      mode == .builtInKeyBinding || resolvedKind == .pipeline ? "" : (modelProvider ?? "")
    let resolvedModelId =
      mode == .builtInKeyBinding || resolvedKind == .pipeline ? "" : (modelId ?? "")
    let resolvedOutputMode: CustomActionOutputMode =
      mode == .builtInKeyBinding ? .resultWindow : outputMode
    let resolvedScript =
      mode == .builtInKeyBinding || resolvedKind == .pipeline
      ? CustomActionConfig.defaultJavaScriptTemplate
      : script
    let normalizedKeyBinding =
      resolvedKind == .keyBinding
      ? SelectionBarKeyboardShortcutParser.normalize(keyBinding)
        ?? keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
      : ""
    let resolvedKeyBindingOverrides =
      mode == .builtInKeyBinding ? normalizedKeyBindingOverrides() : []

    return CustomActionConfig(
      id: existingConfig.id,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? String(localized: "Custom Action") : name,
      prompt: resolvedPrompt,
      modelProvider: resolvedModelProvider,
      modelId: resolvedModelId,
      kind: resolvedKind,
      outputMode: resolvedOutputMode,
      script: resolvedScript,
      keyBinding: normalizedKeyBinding,
      keyBindingOverrides: resolvedKeyBindingOverrides,
      isEnabled: existingConfig.isEnabled,
      isBuiltIn: mode == .builtInKeyBinding,
      templateId: nil,
      icon: iconForSave(),
      includesSourceContext: resolvedKind == .llm && includesSourceContext,
      pipelineSteps: resolvedKind == .pipeline ? pipelineSteps : []
    )
  }

  func normalizedKeyBindingOverrides() -> [CustomActionKeyBindingOverride] {
    var seenBundleIDs: Set<String> = []
    var normalized: [CustomActionKeyBindingOverride] = []

    for override in keyBindingOverrides {
      let bundleID = override.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !bundleID.isEmpty, seenBundleIDs.insert(bundleID).inserted else { continue }

      let appName = override.appName.trimmingCharacters(in: .whitespacesAndNewlines)
      let rawKeyBinding = override.keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        let normalizedKeyBinding =
          SelectionBarKeyboardShortcutParser.normalize(rawKeyBinding)
          ?? (SelectionBarKeyboardShortcutParser.parse(rawKeyBinding) != nil ? rawKeyBinding : nil)
      else { continue }

      normalized.append(
        CustomActionKeyBindingOverride(
          bundleID: bundleID,
          appName: appName,
          keyBinding: normalizedKeyBinding
        )
      )
    }

    return normalized
  }

  private func iconForSave() -> CustomActionIcon? {
    let value = selectedSFSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackKind = mode == .builtInKeyBinding ? CustomActionKind.keyBinding : actionKind
    let defaultValue = defaultIcon(for: fallbackKind).trimmingCharacters(
      in: .whitespacesAndNewlines)
    if value.isEmpty || value == defaultValue {
      return nil
    }
    return CustomActionIcon(value: value)
  }

  private func defaultIcon(for kind: CustomActionKind) -> String {
    var baseline = existingConfig
    baseline.kind = kind
    baseline.templateId = nil
    return baseline.defaultIconSFSymbolName
  }
}
