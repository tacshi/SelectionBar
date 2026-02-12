import Foundation

public enum SelectionBarSpeakProviderKind: Sendable, Equatable {
  case system
  case api
  case custom
}

public struct SelectionBarSpeakProviderOption: Identifiable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let kind: SelectionBarSpeakProviderKind

  public init(id: String, name: String, kind: SelectionBarSpeakProviderKind) {
    self.id = id
    self.name = name
    self.kind = kind
  }
}

/// Built-in system TTS providers for Selection Bar.
public enum SelectionBarSpeakSystemProvider: String, CaseIterable, Sendable {
  case apple = "system-apple"

  public var displayName: String {
    switch self {
    case .apple: "Apple"
    }
  }
}

/// Built-in API-based TTS providers for Selection Bar.
public enum SelectionBarSpeakAPIProvider: String, CaseIterable, Sendable {
  case elevenLabs = "api-elevenlabs"

  public var displayName: String {
    switch self {
    case .elevenLabs: "ElevenLabs"
    }
  }
}

/// An ElevenLabs voice entry.
public struct ElevenLabsVoice: Codable, Sendable, Identifiable, Equatable {
  public let voiceId: String
  public let name: String

  public var id: String { voiceId }

  public init(voiceId: String, name: String) {
    self.voiceId = voiceId
    self.name = name
  }
}
