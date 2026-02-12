import SelectionBarCore
import SwiftUI

private struct ProviderDetailHeaderRow: View {
  let title: String
  let systemIcon: String
  let image: NSImage?

  var body: some View {
    HStack(spacing: 12) {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 28, height: 28)
          .clipShape(.rect(cornerRadius: 6))
      } else {
        Image(systemName: systemIcon)
          .font(.title3)
          .frame(width: 28, height: 28)
      }
      Text(title)
        .font(.headline)
      Spacer()
    }
  }
}

struct OpenAIProviderSettingsDetail: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  let onKeychainChanged: () -> Void

  var body: some View {
    OpenAICompatibleProviderSettingsDetail(
      title: "OpenAI",
      systemIcon: "brain",
      imageName: "openai.png",
      description: "OpenAI supports both LLM chat and translation. You can choose separate models.",
      keychainKey: "openai_api_key",
      apiKeyURL: URL(string: "https://platform.openai.com/api-keys")!,
      apiKeyLinkTitle: "Get API Key from OpenAI",
      modelFetchContext: .init(
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKey: "",
        extraHeaders: [:]
      ),
      defaultModel: SelectionBarSettingsStore.defaultOpenAIModel,
      chatModelSelectorTitle: "Select OpenAI Chat Model",
      translationModelSelectorTitle: "Select OpenAI Translation Model",
      modelFilter: { models in
        let filtered = models.filter {
          $0.hasPrefix("gpt-") || $0.hasPrefix("o1") || $0.hasPrefix("o3")
            || $0.hasPrefix("chatgpt")
        }
        return filtered.isEmpty ? models : filtered
      },
      availableModels: Binding(
        get: { settingsStore.availableOpenAIModels },
        set: { settingsStore.availableOpenAIModels = $0 }
      ),
      chatModel: Binding(
        get: { settingsStore.openAIModel },
        set: { settingsStore.openAIModel = $0 }
      ),
      translationModel: Binding(
        get: { settingsStore.openAITranslationModel },
        set: { settingsStore.openAITranslationModel = $0 }
      ),
      onKeychainChanged: onKeychainChanged
    )
  }
}

struct OpenRouterProviderSettingsDetail: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  let onKeychainChanged: () -> Void

  var body: some View {
    OpenAICompatibleProviderSettingsDetail(
      title: "OpenRouter",
      systemIcon: "network",
      imageName: "openrouter.png",
      description:
        "OpenRouter supports unified LLM chat and translation model routing. You can choose separate models.",
      keychainKey: "openrouter_api_key",
      apiKeyURL: URL(string: "https://openrouter.ai/keys")!,
      apiKeyLinkTitle: "Get API Key from OpenRouter",
      modelFetchContext: .init(
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        apiKey: "",
        extraHeaders: [
          "HTTP-Referer": "https://github.com/tacshi/SelectionBar",
          "X-Title": "SelectionBar",
        ]
      ),
      defaultModel: SelectionBarSettingsStore.defaultOpenRouterModel,
      chatModelSelectorTitle: "Select OpenRouter Chat Model",
      translationModelSelectorTitle: "Select OpenRouter Translation Model",
      modelFilter: { $0 },
      availableModels: Binding(
        get: { settingsStore.availableOpenRouterModels },
        set: { settingsStore.availableOpenRouterModels = $0 }
      ),
      chatModel: Binding(
        get: { settingsStore.openRouterModel },
        set: { settingsStore.openRouterModel = $0 }
      ),
      translationModel: Binding(
        get: { settingsStore.openRouterTranslationModel },
        set: { settingsStore.openRouterTranslationModel = $0 }
      ),
      onKeychainChanged: onKeychainChanged
    )
  }
}

private struct OpenAICompatibleProviderSettingsDetail: View {
  let title: String
  let systemIcon: String
  let imageName: String
  let description: String
  let keychainKey: String
  let apiKeyURL: URL
  let apiKeyLinkTitle: String
  let modelFetchContext: OpenAICompatibleModelService.FetchContext
  let defaultModel: String
  let chatModelSelectorTitle: String
  let translationModelSelectorTitle: String
  let modelFilter: ([String]) -> [String]
  @Binding var availableModels: [String]
  @Binding var chatModel: String
  @Binding var translationModel: String
  let onKeychainChanged: () -> Void

  @State private var apiKey = ""
  @State private var isTesting = false
  @State private var testResult: String?
  @State private var showingModelSelector = false
  @State private var showingTranslationModelSelector = false

  private var filteredModels: [String] {
    modelFilter(availableModels)
  }

  private var displayChatModel: String {
    translationModel.isEmpty ? chatModel : translationModel
  }

  var body: some View {
    Form {
      Section {
        ProviderDetailHeaderRow(
          title: title,
          systemIcon: systemIcon,
          image: ProviderLogoLoader.image(named: imageName)
        )

        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      APIKeySectionWithTest(
        apiKey: $apiKey,
        isTesting: $isTesting,
        testResult: $testResult,
        onTestConnection: { await testConnection() },
        onSaveKey: saveKey,
        onClearKey: clearKey
      )

      Section("Capabilities") {
        capabilityRow(
          title: "Chat Model",
          isEnabled: !filteredModels.isEmpty,
          selectedModel: chatModel,
          buttonAction: { showingModelSelector = true }
        )

        capabilityRow(
          title: "Translation Model",
          isEnabled: !filteredModels.isEmpty,
          selectedModel: displayChatModel,
          defaultDescription: "Uses chat model",
          buttonAction: { showingTranslationModelSelector = true }
        )
      }

      Section {
        Link(destination: apiKeyURL) {
          Label(apiKeyLinkTitle, systemImage: "arrow.up.right.square")
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      APIKeySection.loadKey(from: keychainKey, into: $apiKey)
    }
    .sheet(isPresented: $showingModelSelector) {
      ModelSelectorSheet(
        models: filteredModels,
        selectedModel: Binding(
          get: { chatModel },
          set: { chatModel = $0 }
        ),
        title: chatModelSelectorTitle,
        width: 500,
        height: 450
      )
    }
    .sheet(isPresented: $showingTranslationModelSelector) {
      ModelSelectorSheet(
        models: filteredModels,
        selectedModel: Binding(
          get: { translationModel },
          set: { translationModel = $0 }
        ),
        title: translationModelSelectorTitle,
        showClearOption: true,
        clearOptionLabel: "Use Chat Model",
        width: 500,
        height: 450
      )
    }
  }

  @ViewBuilder
  private func capabilityRow(
    title: String,
    isEnabled: Bool,
    selectedModel: String,
    defaultDescription: String = "Test connection first",
    buttonAction: @escaping () -> Void
  ) -> some View {
    HStack {
      Text(title)
      Spacer()
      if isEnabled {
        Button {
          buttonAction()
        } label: {
          HStack(spacing: 4) {
            Text(selectedModel.isEmpty ? defaultDescription : selectedModel)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: 260, alignment: .trailing)
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.bordered)
        .help(selectedModel)
      } else {
        Text(defaultDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func saveKey() {
    _ = KeychainHelper.shared.save(key: keychainKey, value: apiKey)
    testResult = "Key saved to Keychain."
    onKeychainChanged()
  }

  private func clearKey() {
    _ = KeychainHelper.shared.delete(key: keychainKey)
    apiKey = ""
    availableModels = []
    chatModel = defaultModel
    translationModel = ""
    testResult = "Key cleared from Keychain."
    onKeychainChanged()
  }

  private func testConnection() async -> Result<String, Error> {
    let context = OpenAICompatibleModelService.FetchContext(
      baseURL: modelFetchContext.baseURL,
      apiKey: apiKey,
      extraHeaders: modelFetchContext.extraHeaders
    )

    do {
      let models = try await OpenAICompatibleModelService.fetchModels(context: context)
      let filtered = modelFilter(models)
      await MainActor.run {
        availableModels = filtered
        if let first = filtered.first {
          if !filtered.contains(chatModel) {
            chatModel = first
          }
          if !translationModel.isEmpty
            && !filtered.contains(translationModel)
          {
            translationModel = ""
          }
        }
      }
      return .success("Success! Found \(filtered.count) models.")
    } catch {
      return .failure(error)
    }
  }
}

struct DeepLProviderSettingsDetail: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  let onKeychainChanged: () -> Void
  @State private var apiKey = ""
  @State private var statusMessage: String?

  var body: some View {
    Form {
      Section {
        ProviderDetailHeaderRow(
          title: "DeepL",
          systemIcon: "character.book.closed",
          image: ProviderLogoLoader.image(named: "deepl.png")
        )

        Text("DeepL is translation-only. Chat capability is intentionally disabled.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      APIKeySection(
        apiKey: $apiKey,
        statusMessage: $statusMessage,
        keychainKey: "deepl_api_key",
        onKeychainChanged: onKeychainChanged
      )

      Section("Capabilities") {
        Text("Translation")
        Text("No chat capability")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      APIKeySection.loadKey(from: "deepl_api_key", into: $apiKey)
    }
  }
}

struct CustomProviderSettingsDetail: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  let providerID: UUID
  let onKeychainChanged: () -> Void
  let onDeleted: () -> Void

  @State private var apiKey = ""
  @State private var isTesting = false
  @State private var testResult: String?
  @State private var isEditing = false
  @State private var showDeleteConfirmation = false

  private var provider: CustomLLMProvider? {
    settingsStore.customLLMProvider(id: providerID)
  }

  var body: some View {
    Group {
      if let provider {
        Form {
          Section {
            HStack(spacing: 12) {
              if let iconData = provider.iconData, let iconImage = NSImage(data: iconData) {
                Image(nsImage: iconImage)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 40, height: 40)
                  .clipShape(.rect(cornerRadius: 8))
              } else {
                Image(systemName: "server.rack")
                  .font(.title)
                  .foregroundStyle(.secondary)
                  .frame(width: 40, height: 40)
              }
              VStack(alignment: .leading) {
                Text(provider.name)
                  .bold()
                Text("OpenAI-compatible custom provider")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()

              HStack(spacing: 4) {
                if provider.capabilities.contains(.llm) {
                  capabilityBadge("LLM", color: .blue)
                }
                if provider.capabilities.contains(.translation) {
                  capabilityBadge("Translate", color: .cyan)
                }
              }
            }

            Text(provider.baseURL.absoluteString)
              .font(.system(.body, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          } header: {
            Label("Custom Provider", systemImage: "server.rack")
          }

          APIKeySectionWithTest(
            apiKey: $apiKey,
            isTesting: $isTesting,
            testResult: $testResult,
            showClearKeyButton: false,
            onTestConnection: { await testConnection(for: provider) },
            onSaveKey: { saveKey(for: provider) },
            onClearKey: { clearKey(for: provider) }
          )

          Section {
            HStack {
              Button("Edit") {
                isEditing = true
              }
              .buttonStyle(.bordered)

              Spacer()

              Button("Delete", role: .destructive) {
                showDeleteConfirmation = true
              }
              .buttonStyle(.borderedProminent)
              .tint(.red)
            }
          }

          Section("Capabilities") {
            capabilityRow(
              title: "Chat",
              enabled: provider.capabilities.contains(.llm),
              model: provider.llmModel
            )
            capabilityRow(
              title: "Translation",
              enabled: provider.capabilities.contains(.translation),
              model: provider.translationModel.isEmpty
                ? provider.llmModel : provider.translationModel
            )
          }

          if !provider.models.isEmpty {
            Section("Available Models") {
              ForEach(provider.models.prefix(10), id: \.self) { model in
                Text(model)
                  .font(.system(.body, design: .monospaced))
                  .foregroundStyle(.secondary)
              }
              if provider.models.count > 10 {
                Text("... and \(provider.models.count - 10) more")
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
        .formStyle(.grouped)
        .onAppear {
          APIKeySection.loadKey(from: provider.keychainKey, into: $apiKey)
        }
        .sheet(isPresented: $isEditing) {
          if let currentProvider = settingsStore.customLLMProvider(id: providerID) {
            CustomProviderEditorView(
              provider: currentProvider,
              isEditing: true,
              onSave: { updatedProvider, updatedAPIKey in
                settingsStore.updateCustomLLMProvider(updatedProvider, apiKey: updatedAPIKey)
                APIKeySection.loadKey(from: updatedProvider.keychainKey, into: $apiKey)
                onKeychainChanged()
              }
            )
          }
        }
        .confirmationDialog(
          "Delete Provider?",
          isPresented: $showDeleteConfirmation,
          titleVisibility: .visible
        ) {
          Button("Delete", role: .destructive) {
            settingsStore.removeCustomLLMProvider(id: providerID)
            onDeleted()
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("This provider and its API key will be removed.")
        }
      } else {
        ContentUnavailableView(
          "Provider Not Found",
          systemImage: "exclamationmark.triangle",
          description: Text("This provider no longer exists.")
        )
      }
    }
  }

  @ViewBuilder
  private func capabilityRow(title: String, enabled: Bool, model: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      if enabled {
        if model.isEmpty {
          Text("Enabled")
            .foregroundStyle(.secondary)
        } else {
          Text(model)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 280, alignment: .trailing)
            .foregroundStyle(.secondary)
        }
      } else {
        Text("Disabled")
          .foregroundStyle(.tertiary)
      }
    }
  }

  private func capabilityBadge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption2)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.2))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }

  private func saveKey(for provider: CustomLLMProvider) {
    _ = KeychainHelper.shared.save(key: provider.keychainKey, value: apiKey)
    testResult = "Key saved to Keychain."
    onKeychainChanged()
  }

  private func clearKey(for provider: CustomLLMProvider) {
    _ = KeychainHelper.shared.delete(key: provider.keychainKey)
    apiKey = ""
    testResult = "Key cleared from Keychain."
    onKeychainChanged()
  }

  private func testConnection(for provider: CustomLLMProvider) async -> Result<String, Error> {
    do {
      let context = OpenAICompatibleModelService.FetchContext(
        baseURL: provider.baseURL,
        apiKey: apiKey
      )
      let models = try await OpenAICompatibleModelService.fetchModels(context: context)

      await MainActor.run {
        var updated = provider
        updated.models = models
        if updated.llmModel.isEmpty, let first = models.first {
          updated.llmModel = first
        }
        settingsStore.updateCustomLLMProvider(updated)
      }
      return .success("Success! Found \(models.count) models.")
    } catch {
      return .failure(error)
    }
  }
}
