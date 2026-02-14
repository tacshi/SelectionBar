import Foundation
import Testing

@testable import SelectionBarCore

@Suite("ChatSessionStore Tests")
@MainActor
struct ChatSessionStoreTests {
  private func makeTempDirectory() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ChatSessionStoreTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
  }

  private func makeStore(directory: URL) -> ChatSessionStore {
    ChatSessionStore(sessionsDirectory: directory)
  }

  private func makeRecord(
    id: UUID = UUID(),
    filePath: String = "/Users/test/file.swift",
    messageCount: Int = 2,
    createdAt: Date = Date(),
    lastAccessedAt: Date = Date()
  ) -> ChatSessionRecord {
    var messages: [ChatMessage] = []
    for i in 0..<messageCount {
      messages.append(
        ChatMessage(role: i % 2 == 0 ? .user : .assistant, content: "Message \(i)"))
    }
    return ChatSessionRecord(
      id: id,
      filePath: filePath,
      messages: messages,
      createdAt: createdAt,
      lastAccessedAt: lastAccessedAt
    )
  }

  @Test("Save and load roundtrip")
  func saveLoadRoundtrip() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    let record = makeRecord()
    store.saveSession(record)

    let loaded = store.loadSession(forFilePath: record.filePath)
    #expect(loaded != nil)
    #expect(loaded?.id == record.id)
    #expect(loaded?.filePath == record.filePath)
    #expect(loaded?.messages.count == record.messages.count)
    #expect(loaded?.messages[0].role == .user)
    #expect(loaded?.messages[0].content == "Message 0")
    #expect(loaded?.messages[1].role == .assistant)
    #expect(loaded?.messages[1].content == "Message 1")
  }

  @Test("Load returns nil for non-existent session")
  func loadNonExistent() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    let loaded = store.loadSession(forFilePath: "/no/such/file.swift")
    #expect(loaded == nil)
  }

  @Test("Delete removes session")
  func deleteSession() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    let record = makeRecord()
    store.saveSession(record)
    #expect(store.loadSession(forFilePath: record.filePath) != nil)

    store.deleteSession(forFilePath: record.filePath)
    #expect(store.loadSession(forFilePath: record.filePath) == nil)
  }

  @Test("List sessions sorted by lastAccessedAt descending")
  func listSessionsSorted() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    let now = Date()
    let record1 = makeRecord(
      filePath: "/file1.swift",
      lastAccessedAt: now.addingTimeInterval(-100)
    )
    let record2 = makeRecord(
      filePath: "/file2.swift",
      lastAccessedAt: now.addingTimeInterval(-50)
    )
    let record3 = makeRecord(
      filePath: "/file3.swift",
      lastAccessedAt: now
    )

    store.saveSession(record1)
    store.saveSession(record2)
    store.saveSession(record3)

    let sessions = store.listSessions()
    #expect(sessions.count == 3)
    #expect(sessions[0].filePath == "/file3.swift")
    #expect(sessions[1].filePath == "/file2.swift")
    #expect(sessions[2].filePath == "/file1.swift")
  }

  @Test("Prune keeps only newest sessions within limit")
  func pruneIfNeeded() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    let now = Date()
    for i in 0..<5 {
      let record = makeRecord(
        filePath: "/file\(i).swift",
        lastAccessedAt: now.addingTimeInterval(Double(i) * 10)
      )
      store.saveSession(record)
    }

    store.pruneIfNeeded(limit: 3)
    let sessions = store.listSessions()
    #expect(sessions.count == 3)
    // Newest 3 should remain (file4, file3, file2)
    let paths = sessions.map(\.filePath)
    #expect(paths.contains("/file4.swift"))
    #expect(paths.contains("/file3.swift"))
    #expect(paths.contains("/file2.swift"))
    #expect(!paths.contains("/file0.swift"))
    #expect(!paths.contains("/file1.swift"))
  }

  @Test("Clear all removes everything")
  func clearAll() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    for i in 0..<3 {
      store.saveSession(makeRecord(filePath: "/file\(i).swift"))
    }
    #expect(store.listSessions().count == 3)

    store.clearAll()
    #expect(store.listSessions().isEmpty)
  }

  @Test("SHA-256 hash is consistent")
  func hashConsistency() {
    let hash1 = ChatSessionStore.hashForFilePath("/Users/test/file.swift")
    let hash2 = ChatSessionStore.hashForFilePath("/Users/test/file.swift")
    #expect(hash1 == hash2)
    #expect(hash1.count == 64)  // SHA-256 hex = 64 chars

    let hash3 = ChatSessionStore.hashForFilePath("/Users/test/other.swift")
    #expect(hash1 != hash3)
  }

  @Test("Save preserves multiple sessions for the same file path")
  func savePreservesMultipleSessionsForFile() {
    let dir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = makeStore(directory: dir)

    let now = Date()
    let record1 = makeRecord(
      id: UUID(),
      filePath: "/file.swift",
      messageCount: 2,
      lastAccessedAt: now
    )
    store.saveSession(record1)

    let record2 = makeRecord(
      id: UUID(),
      filePath: "/file.swift",
      messageCount: 4,
      lastAccessedAt: now.addingTimeInterval(10)
    )
    store.saveSession(record2)

    let sessionsForFile = store.listSessions(forFilePath: "/file.swift")
    #expect(sessionsForFile.count == 2)

    let latest = store.loadSession(forFilePath: "/file.swift")
    #expect(latest?.id == record2.id)
    #expect(latest?.messages.count == 4)

    let loadedRecord1 = store.loadSession(forFilePath: "/file.swift", sessionID: record1.id)
    #expect(loadedRecord1?.messages.count == 2)

    let loadedRecord2 = store.loadSession(forFilePath: "/file.swift", sessionID: record2.id)
    #expect(loadedRecord2?.messages.count == 4)
  }
}
