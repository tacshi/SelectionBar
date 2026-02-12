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
  public var ttsModel: String

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
    translationModel: String = "",
    ttsModel: String = ""
  ) {
    self.id = id
    self.name = name
    self.baseURL = baseURL
    self.iconData = iconData
    self.models = models
    self.capabilities = capabilities
    self.llmModel = llmModel
    self.translationModel = translationModel
    self.ttsModel = ttsModel
  }

  // MARK: - Codable (backward-compatible)

  private enum CodingKeys: String, CodingKey {
    case id, name, baseURL, iconData, models, capabilities
    case llmModel, translationModel, ttsModel
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    baseURL = try container.decode(URL.self, forKey: .baseURL)
    iconData = try container.decodeIfPresent(Data.self, forKey: .iconData)
    models = try container.decode([String].self, forKey: .models)
    capabilities = try container.decode(ProviderCapabilities.self, forKey: .capabilities)
    llmModel = try container.decode(String.self, forKey: .llmModel)
    translationModel = try container.decode(String.self, forKey: .translationModel)
    ttsModel = try container.decodeIfPresent(String.self, forKey: .ttsModel) ?? ""
  }
}
