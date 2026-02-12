import SelectionBarCore
import SwiftUI

// MARK: - Provider Presets

/// Preset templates for popular OpenAI-compatible providers.
enum ProviderPreset: String, CaseIterable, Identifiable {
  case custom = "custom"
  case togetherAI = "together"
  case groq = "groq"
  case fireworks = "fireworks"
  case deepseek = "deepseek"
  case mistral = "mistral"
  case nvidia = "nvidia"
  case perplexity = "perplexity"
  case volcengine = "volcengine"
  case lmStudio = "lmstudio"
  case ollamaOpenAI = "ollama"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .custom: String(localized: "Custom Provider")
    case .togetherAI: "Together AI"
    case .groq: "Groq"
    case .fireworks: "Fireworks AI"
    case .deepseek: "DeepSeek"
    case .mistral: "Mistral AI"
    case .nvidia: "Nvidia NIM"
    case .perplexity: "Perplexity"
    case .volcengine: String(localized: "Volcengine Ark (Doubao)")
    case .lmStudio: String(localized: "LM Studio (Local)")
    case .ollamaOpenAI: String(localized: "Ollama OpenAI API (Local)")
    }
  }

  var baseURL: URL {
    switch self {
    case .custom: URL(string: "https://")!
    case .togetherAI: URL(string: "https://api.together.xyz/v1")!
    case .groq: URL(string: "https://api.groq.com/openai/v1")!
    case .fireworks: URL(string: "https://api.fireworks.ai/inference/v1")!
    case .deepseek: URL(string: "https://api.deepseek.com/v1")!
    case .mistral: URL(string: "https://api.mistral.ai/v1")!
    case .nvidia: URL(string: "https://integrate.api.nvidia.com/v1")!
    case .perplexity: URL(string: "https://api.perplexity.ai")!
    case .volcengine: URL(string: "https://ark.cn-beijing.volces.com/api/v3")!
    case .lmStudio: URL(string: "http://localhost:1234/v1")!
    case .ollamaOpenAI: URL(string: "http://localhost:11434/v1")!
    }
  }

  var llmModel: String {
    switch self {
    case .custom: ""
    case .togetherAI: "meta-llama/Llama-3.3-70B-Instruct-Turbo"
    case .groq: "llama-3.3-70b-versatile"
    case .fireworks: "accounts/fireworks/models/llama-v3p3-70b-instruct"
    case .deepseek: "deepseek-chat"
    case .mistral: "mistral-large-latest"
    case .nvidia: "meta/llama-3.1-405b-instruct"
    case .perplexity: "sonar"
    case .volcengine: ""
    case .lmStudio: ""
    case .ollamaOpenAI: ""
    }
  }

  var defaultCapabilities: ProviderCapabilities {
    [.llm]
  }

  var requiresAPIKey: Bool {
    switch self {
    case .lmStudio, .ollamaOpenAI: false
    default: true
    }
  }

  var helpText: String? {
    switch self {
    case .volcengine: String(localized: "Use your endpoint ID as the model name")
    case .lmStudio: String(localized: "Start LM Studio with server mode enabled")
    case .ollamaOpenAI: String(localized: "Requires Ollama running locally")
    default: nil
    }
  }

  /// Logo file name in Resources/ProviderLogos.
  var logoFileName: String? {
    switch self {
    case .custom: nil
    case .togetherAI: "together.png"
    case .groq: "groq.png"
    case .fireworks: "fireworks.png"
    case .deepseek: "deepseek.png"
    case .mistral: "mistral.png"
    case .nvidia: "nvidia.png"
    case .perplexity: "perplexity.png"
    case .volcengine: "volcengine.png"
    case .lmStudio: "lmstudio.png"
    case .ollamaOpenAI: "ollama.png"
    }
  }

  /// Load icon data from bundle.
  var iconData: Data? {
    let resourceName =
      logoFileName.map { ($0 as NSString).deletingPathExtension } ?? ""
    let resourceExtension =
      logoFileName.map { ($0 as NSString).pathExtension } ?? ""
    guard logoFileName != nil,
      let url = Bundle.module.url(
        forResource: resourceName,
        withExtension: resourceExtension.isEmpty ? nil : resourceExtension
      ),
      let data = try? Data(contentsOf: url)
    else {
      return nil
    }
    return data
  }

  /// Presets that should appear first (most popular).
  static var popular: [ProviderPreset] {
    [.deepseek, .groq, .nvidia, .togetherAI, .mistral]
  }

  /// Local/self-hosted presets.
  static var local: [ProviderPreset] {
    [.lmStudio, .ollamaOpenAI]
  }

  /// Other cloud presets.
  static var other: [ProviderPreset] {
    [.fireworks, .perplexity, .volcengine]
  }
}

/// View for adding or editing a custom OpenAI-compatible provider.
struct CustomProviderEditorView: View {
  @Environment(\.dismiss) private var dismiss

  /// The provider being edited (or new provider if isEditing is false)
  @State var provider: CustomLLMProvider

  /// Base URL as a string for reliable TextField binding
  @State private var baseURLString: String = "https://"

  /// API key for the provider
  @State private var apiKey: String = ""

  /// Whether we're editing an existing provider vs creating a new one
  let isEditing: Bool

  /// Callback when provider is saved
  let onSave: (CustomLLMProvider, String) -> Void

  // MARK: - Preset Selection

  @State private var selectedPreset: ProviderPreset = .custom

  // MARK: - Connection Testing

  @State private var isTesting: Bool = false
  @State private var testResult: TestResult?

  enum TestResult {
    case success(models: [String])
    case failure(error: String)
  }

  // MARK: - Validation

  private var isValidURL: Bool {
    guard !baseURLString.isEmpty, baseURLString != "https://" else {
      return false
    }
    guard let url = URL(string: baseURLString) else {
      return false
    }
    return url.scheme == "http" || url.scheme == "https"
  }

  private var canSave: Bool {
    let apiKeyValid = selectedPreset.requiresAPIKey ? !apiKey.isEmpty : true
    return !provider.name.isEmpty && apiKeyValid && isValidURL
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text(
          isEditing
            ? String(localized: "Edit Provider")
            : String(localized: "Add Custom Provider")
        )
        .font(.headline)
        Spacer()
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape, modifiers: [])
      }
      .padding()

      Divider()

      // Form
      Form {
        // Preset picker (only show when adding new provider)
        if !isEditing {
          Section("Quick Setup") {
            Picker("Provider Template", selection: $selectedPreset) {
              Text("Custom").tag(ProviderPreset.custom)

              Section("Popular") {
                ForEach(ProviderPreset.popular) { preset in
                  Text(preset.displayName).tag(preset)
                }
              }

              Section("Local") {
                ForEach(ProviderPreset.local) { preset in
                  Text(preset.displayName).tag(preset)
                }
              }

              Section("Other") {
                ForEach(ProviderPreset.other) { preset in
                  Text(preset.displayName).tag(preset)
                }
              }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPreset) { _, newPreset in
              applyPreset(newPreset)
            }

            if let helpText = selectedPreset.helpText {
              Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        Section("Provider Details") {
          TextField("Name", text: $provider.name)
            .textFieldStyle(.roundedBorder)
            .help("Display name (e.g., 'Volcengine Doubao', 'Together AI')")

          TextField("Base URL", text: $baseURLString)
            .textFieldStyle(.roundedBorder)
            .help("API endpoint (e.g., https://api.together.xyz/v1)")
            .onChange(of: baseURLString) { _, newValue in
              if let url = URL(string: newValue) {
                provider.baseURL = url
              }
            }

          if !isValidURL && !baseURLString.isEmpty && baseURLString != "https://" {
            Text("Please enter a valid URL starting with http:// or https://")
              .font(.caption)
              .foregroundStyle(.red)
          }
        }

        Section("Authentication") {
          if selectedPreset.requiresAPIKey {
            SecureField("API Key", text: $apiKey)
              .textFieldStyle(.roundedBorder)
              .onChange(of: apiKey) { _, _ in
                testResult = nil
              }
          } else {
            Text("No API key required for local providers")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          HStack {
            if isTesting {
              ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
            }

            Button("Test Connection") {
              testConnection()
            }
            .buttonStyle(.bordered)
            .disabled((selectedPreset.requiresAPIKey && apiKey.isEmpty) || !isValidURL || isTesting)

            Spacer()
          }

          if let result = testResult {
            testResultView(result)
          }
        }

        Section("Capabilities") {
          let hasModels = !provider.models.isEmpty

          if !hasModels {
            Text("Test connection to enable capabilities")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Toggle("LLM (Chat)", isOn: capabilityBinding(.llm))
            .disabled(!hasModels)
          if provider.capabilities.contains(.llm) && hasModels {
            modelPicker(
              target: .llm,
              selection: $provider.llmModel,
              placeholder: "Select LLM model"
            )
          }

          Toggle("Translation", isOn: capabilityBinding(.translation))
            .disabled(!hasModels || !provider.capabilities.contains(.llm))
          if provider.capabilities.contains(.translation) && hasModels {
            modelPicker(
              target: .translation,
              selection: $provider.translationModel,
              placeholder: "Select translation model"
            )
          }

          Toggle(String(localized: "Text-to-Speech"), isOn: capabilityBinding(.tts))
            .disabled(!hasModels)
          if provider.capabilities.contains(.tts) && hasModels {
            modelPicker(
              target: .tts,
              selection: $provider.ttsModel,
              placeholder: String(localized: "Select TTS model")
            )
          }
        }
      }
      .formStyle(.grouped)
      .sheet(item: $activeModelSelector) { target in
        let binding: Binding<String> = Binding(
          get: {
            switch target {
            case .llm:
              provider.llmModel
            case .translation:
              provider.translationModel
            case .tts:
              provider.ttsModel
            }
          },
          set: { newValue in
            switch target {
            case .llm:
              provider.llmModel = newValue
            case .translation:
              provider.translationModel = newValue
            case .tts:
              provider.ttsModel = newValue
            }
          }
        )

        ModelSelectorSheet(
          models: provider.models,
          selectedModel: binding,
          width: 500,
          height: 450
        )
      }

      Divider()

      // Footer
      HStack {
        Spacer()
        Button(isEditing ? String(localized: "Save") : String(localized: "Add Provider")) {
          saveProvider()
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!canSave)
        .buttonStyle(.borderedProminent)
      }
      .padding()
    }
    .frame(width: 450, height: 650)
    .onAppear {
      baseURLString = provider.baseURL.absoluteString
      loadExistingAPIKey()
      if !isEditing && provider.models.isEmpty {
        provider.capabilities = []
      }
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private func testResultView(_ result: TestResult) -> some View {
    switch result {
    case .success(let models):
      Label(
        String(localized: "Connected! Found \(models.count) models"),
        systemImage: "checkmark.circle.fill"
      )
      .foregroundStyle(.green)
      .font(.callout)
    case .failure(let error):
      Label(error, systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.callout)
    }
  }

  // MARK: - Helpers

  /// Creates a binding for a specific capability flag.
  private func capabilityBinding(_ capability: ProviderCapabilities) -> Binding<Bool> {
    Binding(
      get: { provider.capabilities.contains(capability) },
      set: { isOn in
        // Create a new provider struct to ensure SwiftUI detects the change.
        var updated = provider
        if isOn {
          updated.capabilities = updated.capabilities.union(capability)
          if capability == .translation {
            updated.capabilities = updated.capabilities.union(.llm)
          }
        } else {
          updated.capabilities = updated.capabilities.subtracting(capability)
          if capability == .llm {
            // Removing LLM also removes translation, but NOT tts.
            updated.capabilities = updated.capabilities.subtracting(.translation)
          }
        }
        provider = updated
      }
    )
  }

  /// State for the model selector sheet.
  private enum ModelSelectorTarget: Int, Identifiable {
    case llm
    case translation
    case tts

    var id: Int { rawValue }
  }

  @State private var activeModelSelector: ModelSelectorTarget?

  /// Creates a model picker view for a capability.
  @ViewBuilder
  private func modelPicker(
    target: ModelSelectorTarget,
    selection: Binding<String>,
    placeholder: String
  ) -> some View {
    HStack {
      Text("Model")
        .foregroundStyle(.secondary)

      Spacer()

      Button {
        activeModelSelector = target
      } label: {
        HStack(spacing: 4) {
          if provider.models.isEmpty {
            Text("Test connection first")
              .foregroundStyle(.secondary)
          } else {
            Text(selection.wrappedValue.isEmpty ? placeholder : selection.wrappedValue)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: 180, alignment: .leading)
              .foregroundStyle(selection.wrappedValue.isEmpty ? .secondary : .primary)
          }
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.bordered)
      .disabled(provider.models.isEmpty)
      .help(selection.wrappedValue.isEmpty ? "" : selection.wrappedValue)
    }
  }

  // MARK: - Actions

  private func loadExistingAPIKey() {
    if isEditing {
      if let key = KeychainHelper.shared.readString(key: provider.keychainKey) {
        apiKey = key
      }
    }
  }

  private func testConnection() {
    isTesting = true
    testResult = nil

    Task {
      do {
        let testKey = selectedPreset.requiresAPIKey ? apiKey : "placeholder"
        let context = OpenAICompatibleModelService.FetchContext(
          baseURL: provider.baseURL,
          apiKey: testKey
        )
        let models = try await OpenAICompatibleModelService.fetchModels(context: context)
        await MainActor.run {
          testResult = .success(models: models)
          provider.models = models
          if provider.capabilities.isEmpty {
            provider.capabilities =
              selectedPreset.defaultCapabilities.isEmpty
              ? [.llm] : selectedPreset.defaultCapabilities
          }
          if provider.llmModel.isEmpty, let firstModel = models.first {
            provider.llmModel = firstModel
          }
          isTesting = false
        }
      } catch {
        await MainActor.run {
          testResult = .failure(error: error.localizedDescription)
          isTesting = false
        }
      }
    }
  }

  private func saveProvider() {
    onSave(provider, apiKey)
    dismiss()
  }

  private func applyPreset(_ preset: ProviderPreset) {
    guard preset != .custom else { return }

    baseURLString = preset.baseURL.absoluteString

    provider = CustomLLMProvider(
      id: provider.id,
      name: preset.displayName,
      baseURL: preset.baseURL,
      iconData: preset.iconData,
      models: [],
      capabilities: [],
      llmModel: preset.llmModel,
      translationModel: "",
      ttsModel: ""
    )

    testResult = nil

    if !preset.requiresAPIKey {
      apiKey = ""
    }
  }
}
