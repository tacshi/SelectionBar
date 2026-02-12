import SelectionBarCore
import SwiftUI

enum ProviderLogoLoader {
  static func image(named fileName: String) -> NSImage? {
    let resourceName = (fileName as NSString).deletingPathExtension
    let resourceExtension = (fileName as NSString).pathExtension
    guard
      let url = Bundle.module.url(
        forResource: resourceName,
        withExtension: resourceExtension.isEmpty ? nil : resourceExtension
      )
    else {
      return nil
    }
    return NSImage(contentsOf: url)
  }
}

private enum ProviderSelection: Hashable {
  case openAI
  case openRouter
  case deepL
  case custom(UUID)
}

struct ProvidersSettingsSections: View {
  @Bindable var settingsStore: SelectionBarSettingsStore

  @State private var selectedProvider: ProviderSelection? = .openAI
  @State private var showAddCustomProvider = false

  var body: some View {
    HStack(spacing: 0) {
      List(selection: $selectedProvider) {
        Section {
          ProviderSidebarRow(
            title: "OpenAI",
            systemIcon: "brain",
            image: ProviderLogoLoader.image(named: "openai.png"),
            isConfigured: isOpenAIConfigured
          )
          .tag(ProviderSelection.openAI)

          ProviderSidebarRow(
            title: "OpenRouter",
            systemIcon: "network",
            image: ProviderLogoLoader.image(named: "openrouter.png"),
            isConfigured: isOpenRouterConfigured
          )
          .tag(ProviderSelection.openRouter)
        } header: {
          Label("LLM", systemImage: "brain")
        }

        Section {
          ProviderSidebarRow(
            title: "DeepL",
            systemIcon: "character.book.closed",
            image: ProviderLogoLoader.image(named: "deepl.png"),
            isConfigured: isDeepLConfigured
          )
          .tag(ProviderSelection.deepL)
        } header: {
          Label("Translation", systemImage: "character.book.closed")
        }

        Section {
          ForEach(settingsStore.customLLMProviders) { provider in
            ProviderSidebarRow(
              title: provider.name,
              systemIcon: "server.rack",
              image: provider.iconData.flatMap(NSImage.init(data:)),
              isConfigured: settingsStore.isCustomProviderAPIKeyConfigured(id: provider.id)
            )
            .tag(ProviderSelection.custom(provider.id))
          }

          Button {
            showAddCustomProvider = true
          } label: {
            HStack {
              Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 20, alignment: .center)
              Text("Add Provider")
                .foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
        } header: {
          Label("Custom Providers", systemImage: "server.rack")
        }
      }
      .frame(width: 240)
      .listStyle(.sidebar)

      Divider()

      Group {
        if let selectedProvider {
          switch selectedProvider {
          case .openAI:
            OpenAIProviderSettingsDetail(
              settingsStore: settingsStore,
              onKeychainChanged: refreshProviderConfiguration
            )
          case .openRouter:
            OpenRouterProviderSettingsDetail(
              settingsStore: settingsStore,
              onKeychainChanged: refreshProviderConfiguration
            )
          case .deepL:
            DeepLProviderSettingsDetail(
              settingsStore: settingsStore,
              onKeychainChanged: refreshProviderConfiguration
            )
          case .custom(let providerID):
            if settingsStore.customLLMProvider(id: providerID) != nil {
              CustomProviderSettingsDetail(
                settingsStore: settingsStore,
                providerID: providerID,
                onKeychainChanged: refreshProviderConfiguration,
                onDeleted: {
                  self.selectedProvider = .openAI
                }
              )
            } else {
              ContentUnavailableView(
                "Provider Not Found",
                systemImage: "exclamationmark.triangle",
                description: Text("This provider no longer exists.")
              )
            }
          }
        } else {
          ContentUnavailableView(
            "Select a Provider",
            systemImage: "server.rack",
            description: Text("Choose a provider from the sidebar.")
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .sheet(isPresented: $showAddCustomProvider) {
      CustomProviderEditorView(
        provider: CustomLLMProvider(
          name: "",
          baseURL: URL(string: "https://")!,
          models: [],
          capabilities: [.llm],
          llmModel: "",
          translationModel: ""
        ),
        isEditing: false,
        onSave: { provider, apiKey in
          settingsStore.addCustomLLMProvider(provider, apiKey: apiKey)
          selectedProvider = .custom(provider.id)
        }
      )
    }
    .onAppear {
      settingsStore.refreshCredentialAvailability()
      syncSelection(with: settingsStore.customLLMProviders)
    }
    .onChange(of: settingsStore.customLLMProviders) { _, newProviders in
      syncSelection(with: newProviders)
    }
  }

  private var isOpenAIConfigured: Bool {
    !settingsStore.availableOpenAIModels.isEmpty || settingsStore.openAIAPIKeyConfigured
  }

  private var isOpenRouterConfigured: Bool {
    !settingsStore.availableOpenRouterModels.isEmpty || settingsStore.openRouterAPIKeyConfigured
  }

  private var isDeepLConfigured: Bool {
    settingsStore.deepLAPIKeyConfigured
  }

  private func refreshProviderConfiguration() {
    settingsStore.handleCredentialChange()
  }

  private func syncSelection(with providers: [CustomLLMProvider]) {
    guard let selectedProvider else {
      self.selectedProvider = .openAI
      return
    }

    if case .custom(let id) = selectedProvider {
      guard providers.contains(where: { $0.id == id }) else {
        self.selectedProvider = .openAI
        return
      }
    }
  }
}

private struct ProviderSidebarRow: View {
  let title: String
  let systemIcon: String
  let image: NSImage?
  let isConfigured: Bool

  var body: some View {
    HStack {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 20, height: 20)
          .clipShape(.rect(cornerRadius: 4))
      } else {
        Image(systemName: systemIcon)
          .frame(width: 20)
      }
      Text(title)
      Spacer()
      if isConfigured {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.caption)
      }
    }
  }
}
