import SelectionBarCore
import SwiftUI

/// Reusable credentials section for Keychain-backed API keys.
struct APIKeySection: View {
  @Binding var apiKey: String
  @Binding var statusMessage: String?
  let keychainKey: String
  var keychainService: KeychainServiceProtocol = KeychainHelper.shared
  var onKeychainChanged: () -> Void = {}

  @State private var localKeyText = ""

  private var hasKey: Bool {
    !localKeyText.isEmpty
  }

  var body: some View {
    Section("Credentials") {
      SecureField("API Key", text: $localKeyText)
        .textFieldStyle(.roundedBorder)
        .onChange(of: localKeyText) { _, newValue in
          apiKey = newValue
          statusMessage = nil
        }
        .onChange(of: apiKey) { _, newValue in
          if newValue != localKeyText {
            localKeyText = newValue
          }
        }
        .onAppear {
          localKeyText = apiKey
        }

      HStack {
        Spacer()
        Button("Save Key") {
          _ = keychainService.save(key: keychainKey, value: apiKey)
          statusMessage = String(localized: "Key saved to Keychain.")
          onKeychainChanged()
        }
        .buttonStyle(.bordered)
        .disabled(!hasKey)

        Button("Clear Key", role: .destructive) {
          _ = keychainService.delete(key: keychainKey)
          localKeyText = ""
          apiKey = ""
          statusMessage = String(localized: "Key cleared.")
          onKeychainChanged()
        }
        .buttonStyle(.bordered)
        .disabled(!hasKey)
      }

      if let statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(statusMessage.localizedStandardContains("saved") ? .green : .secondary)
      }
    }
  }
}

extension APIKeySection {
  static func loadKey(
    from keychainKey: String,
    into binding: Binding<String>,
    using service: KeychainServiceProtocol = KeychainHelper.shared
  ) {
    if let key = service.readString(key: keychainKey) {
      binding.wrappedValue = key
    }
  }
}
