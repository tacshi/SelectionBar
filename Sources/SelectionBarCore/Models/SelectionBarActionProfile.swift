import Foundation

/// Per-app override for the configurable Selection Bar action list.
public struct SelectionBarActionProfile: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var app: IgnoredApp
  public var isEnabled: Bool
  public var actionIDs: [UUID] {
    didSet { actionIDs = Self.uniqued(actionIDs) }
  }

  public init(
    id: UUID = UUID(),
    app: IgnoredApp,
    isEnabled: Bool = true,
    actionIDs: [UUID] = []
  ) {
    self.id = id
    self.app = app
    self.isEnabled = isEnabled
    self.actionIDs = Self.uniqued(actionIDs)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case app
    case isEnabled
    case actionIDs
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    app = try container.decode(IgnoredApp.self, forKey: .app)
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    actionIDs = Self.uniqued(
      try container.decodeIfPresent([UUID].self, forKey: .actionIDs) ?? []
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(app, forKey: .app)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(Self.uniqued(actionIDs), forKey: .actionIDs)
  }

  public static func uniqued(_ ids: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    var ordered: [UUID] = []
    for id in ids where seen.insert(id).inserted {
      ordered.append(id)
    }
    return ordered
  }
}

public struct SelectionBarActionProfileStatus: Equatable, Sendable {
  public let validActionCount: Int
  public let missingActionCount: Int
  public let invalidActionCount: Int

  public init(validActionCount: Int, missingActionCount: Int, invalidActionCount: Int) {
    self.validActionCount = validActionCount
    self.missingActionCount = missingActionCount
    self.invalidActionCount = invalidActionCount
  }

  public var hasIssues: Bool {
    missingActionCount > 0 || invalidActionCount > 0
  }
}
