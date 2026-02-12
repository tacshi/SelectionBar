import Foundation

/// Capabilities supported by an LLM provider.
public struct ProviderCapabilities: OptionSet, Codable, Sendable, Hashable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Chat completions.
  public static let llm = ProviderCapabilities(rawValue: 1 << 0)

  /// Text translation via LLM.
  public static let translation = ProviderCapabilities(rawValue: 1 << 1)
}
