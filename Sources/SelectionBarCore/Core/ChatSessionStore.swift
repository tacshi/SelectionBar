import CryptoKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "ChatSessionStore")

public struct ChatSessionRecord: Codable, Sendable, Identifiable {
  public let id: UUID
  public let filePath: String
  public var messages: [ChatMessage]
  public var sourceReadHistory: [String]
  public var createdAt: Date
  public var lastAccessedAt: Date

  public init(
    id: UUID = UUID(),
    filePath: String,
    messages: [ChatMessage],
    sourceReadHistory: [String] = [],
    createdAt: Date,
    lastAccessedAt: Date
  ) {
    self.id = id
    self.filePath = filePath
    self.messages = messages
    self.sourceReadHistory = sourceReadHistory
    self.createdAt = createdAt
    self.lastAccessedAt = lastAccessedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    filePath = try container.decode(String.self, forKey: .filePath)
    messages = try container.decode([ChatMessage].self, forKey: .messages)
    sourceReadHistory =
      try container.decodeIfPresent([String].self, forKey: .sourceReadHistory) ?? []
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    lastAccessedAt = try container.decode(Date.self, forKey: .lastAccessedAt)
  }
}

@MainActor
public final class ChatSessionStore {
  private let sessionsDirectory: URL

  public init(sessionsDirectory: URL? = nil) {
    if let sessionsDirectory {
      self.sessionsDirectory = sessionsDirectory
    } else {
      let appSupport: URL
      if let directory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first {
        appSupport = directory
      } else {
        logger.error(
          "Failed to locate application support directory, falling back to temporary directory.")
        appSupport = FileManager.default.temporaryDirectory
      }
      self.sessionsDirectory = appSupport.appendingPathComponent("SelectionBar/sessions")
    }
    ensureDirectoryExists()
  }

  private func ensureDirectoryExists() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: sessionsDirectory.path) {
      try? fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }
  }

  public func loadSession(forFilePath filePath: String) -> ChatSessionRecord? {
    listSessions(forFilePath: filePath).first
  }

  public func loadSession(forFilePath filePath: String, sessionID: UUID) -> ChatSessionRecord? {
    listSessions(forFilePath: filePath).first { $0.id == sessionID }
  }

  public func saveSession(_ record: ChatSessionRecord) {
    let fileURL = sessionFileURL(for: record.filePath, sessionID: record.id)
    guard let data = try? JSONEncoder().encode(record) else {
      logger.error("Failed to encode session for \(record.filePath, privacy: .public)")
      return
    }
    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      logger.error(
        "Failed to save session: \(error.localizedDescription, privacy: .public)")
    }
  }

  public func deleteSession(forFilePath filePath: String) {
    for session in listSessions(forFilePath: filePath) {
      deleteSession(forFilePath: filePath, sessionID: session.id)
    }
  }

  public func deleteSession(forFilePath filePath: String, sessionID: UUID) {
    let fileURL = sessionFileURL(for: filePath, sessionID: sessionID)
    try? FileManager.default.removeItem(at: fileURL)
  }

  public func listSessions() -> [ChatSessionRecord] {
    let fm = FileManager.default
    guard
      let files = try? fm.contentsOfDirectory(
        at: sessionsDirectory, includingPropertiesForKeys: nil)
    else {
      return []
    }

    var records: [ChatSessionRecord] = []
    let decoder = JSONDecoder()
    for file in files where file.pathExtension == "json" {
      guard let data = try? Data(contentsOf: file),
        let record = try? decoder.decode(ChatSessionRecord.self, from: data)
      else { continue }
      records.append(record)
    }

    return records.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
  }

  public func listSessions(forFilePath filePath: String) -> [ChatSessionRecord] {
    listSessions().filter { $0.filePath == filePath }
  }

  public func pruneIfNeeded(limit: Int) {
    let sessions = listSessions()
    guard sessions.count > limit else { return }

    let toDelete = sessions.suffix(from: limit)
    for session in toDelete {
      deleteSession(forFilePath: session.filePath, sessionID: session.id)
    }
  }

  public func clearAll() {
    let fm = FileManager.default
    guard
      let files = try? fm.contentsOfDirectory(
        at: sessionsDirectory, includingPropertiesForKeys: nil)
    else { return }

    for file in files where file.pathExtension == "json" {
      try? fm.removeItem(at: file)
    }
  }

  // MARK: - File naming

  private func sessionFileURL(for filePath: String, sessionID: UUID) -> URL {
    let hash = SHA256.hash(data: Data(filePath.utf8))
    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
    return sessionsDirectory.appendingPathComponent(
      "\(hashString)-\(sessionID.uuidString.lowercased()).json")
  }

  /// Exposed for testing: returns the SHA-256 hash string for a given file path.
  static func hashForFilePath(_ filePath: String) -> String {
    let hash = SHA256.hash(data: Data(filePath.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }
}
