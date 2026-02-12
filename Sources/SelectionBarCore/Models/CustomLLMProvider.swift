import Foundation

/// A user-defined OpenAI-compatible provider.
public struct CustomLLMProvider: Identifiable, Codable, Sendable, Hashable {
  public let id: UUID
  public var name: String
  public var baseURL: URL
  public var iconData: Data?
  public var models: [String]
  public var capabilities: ProviderCapabilities
  public var llmModel: String
  public var translationModel: String

  /// Keychain key derived from provider ID.
  public var keychainKey: String {
    "custom_llm_\(id.uuidString.lowercased())"
  }

  /// Stable provider identifier for settings/pickers.
  public var providerId: String {
    "custom-\(id.uuidString.lowercased())"
  }

  public init(
    id: UUID = UUID(),
    name: String,
    baseURL: URL,
    iconData: Data? = nil,
    models: [String] = [],
    capabilities: ProviderCapabilities = [.llm],
    llmModel: String = "",
    translationModel: String = ""
  ) {
    self.id = id
    self.name = name
    self.baseURL = baseURL
    self.iconData = iconData
    self.models = models
    self.capabilities = capabilities
    self.llmModel = llmModel
    self.translationModel = translationModel
  }
}
