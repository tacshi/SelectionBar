import SwiftUI

/// Credentials section with async connection test support.
struct APIKeySectionWithTest: View {
  @Binding var apiKey: String
  @Binding var isTesting: Bool
  @Binding var testResult: String?
  var showClearKeyButton: Bool = true

  let onTestConnection: () async -> Result<String, Error>
  let onSaveKey: () -> Void
  let onClearKey: () -> Void

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
          testResult = nil
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
        if isTesting {
          ProgressView()
            .scaleEffect(0.5)
            .frame(width: 16, height: 16)
        }

        Button("Test Connection") {
          testConnection()
        }
        .buttonStyle(.bordered)
        .disabled(!hasKey || isTesting)

        Spacer()

        Button("Save Key") {
          onSaveKey()
        }
        .buttonStyle(.bordered)
        .disabled(!hasKey)

        if showClearKeyButton {
          Button("Clear Key", role: .destructive) {
            onClearKey()
            localKeyText = ""
          }
          .buttonStyle(.bordered)
          .disabled(!hasKey)
        }
      }

      if let testResult {
        Text(testResult)
          .font(.caption)
          .foregroundStyle(isSuccessMessage(testResult) ? .green : .red)
      }
    }
  }

  private func testConnection() {
    isTesting = true
    testResult = nil

    Task {
      let result = await onTestConnection()
      await MainActor.run {
        switch result {
        case .success(let message):
          testResult = message
        case .failure(let error):
          testResult = error.localizedDescription
        }
        isTesting = false
      }
    }
  }

  private func isSuccessMessage(_ message: String) -> Bool {
    let successPatterns = ["Success", "saved", "cleared"]
    return successPatterns.contains { message.localizedStandardContains($0) }
  }
}
