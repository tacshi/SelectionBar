import SelectionBarCore
import SwiftUI

struct ElevenLabsProviderSettingsDetail: View {
  @Bindable var settingsStore: SelectionBarSettingsStore
  let onKeychainChanged: () -> Void

  @State private var apiKey = ""
  @State private var isTesting = false
  @State private var testResult: String?

  private static let models: [(id: String, label: String)] = [
    ("eleven_v3", "v3"),
    ("eleven_turbo_v2_5", "Turbo v2.5"),
    ("eleven_flash_v2_5", "Flash v2.5"),
    ("eleven_multilingual_v2", "Multilingual v2"),
  ]

  var body: some View {
    Form {
      Section {
        ProviderDetailHeaderRow(
          title: "ElevenLabs",
          systemIcon: "speaker.wave.2",
          image: ProviderLogoLoader.image(named: "elevenlabs.png")
        )

        Text("ElevenLabs is a TTS-only provider for high-quality text-to-speech.")
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

      Section("Model") {
        Picker("Model", selection: $settingsStore.elevenLabsModelId) {
          ForEach(Self.models, id: \.id) { model in
            Text(model.label).tag(model.id)
          }
        }
      }

      Section("Capabilities") {
        Text("Text-to-Speech")
        Text("No chat capability")
          .foregroundStyle(.secondary)
      }

      Section {
        Link(
          destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
        ) {
          Label("Get API Key from ElevenLabs", systemImage: "arrow.up.right.square")
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      APIKeySection.loadKey(from: "elevenlabs_api_key", into: $apiKey)
    }
  }

  private func saveKey() {
    _ = KeychainHelper.shared.save(key: "elevenlabs_api_key", value: apiKey)
    testResult = String(localized: "Key saved to Keychain.")
    onKeychainChanged()
  }

  private func clearKey() {
    _ = KeychainHelper.shared.delete(key: "elevenlabs_api_key")
    apiKey = ""
    settingsStore.availableElevenLabsVoices = []
    settingsStore.elevenLabsVoiceId = ""
    testResult = String(localized: "Key cleared from Keychain.")
    onKeychainChanged()
  }

  private func testConnection() async -> Result<String, Error> {
    let currentKey = apiKey
    let client = SelectionBarElevenLabsClient(
      apiKeyReader: { _ in currentKey }
    )

    do {
      let voices = try await client.fetchVoices()
      await MainActor.run {
        settingsStore.availableElevenLabsVoices = voices
        if !voices.isEmpty {
          if !voices.contains(where: { $0.voiceId == settingsStore.elevenLabsVoiceId }) {
            settingsStore.elevenLabsVoiceId = voices[0].voiceId
          }
        }
      }
      return .success(String(localized: "Success! Found \(voices.count) voices."))
    } catch {
      return .failure(error)
    }
  }
}
