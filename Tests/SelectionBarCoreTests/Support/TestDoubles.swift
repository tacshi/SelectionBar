import Foundation

@testable import SelectionBarCore

final class InMemoryKeychain: KeychainServiceProtocol, @unchecked Sendable {
  private(set) var values: [String: String] = [:]
  private(set) var saveCalls: [(String, String)] = []
  private(set) var deleteCalls: [String] = []

  func save(key: String, value: String) -> Bool {
    values[key] = value
    saveCalls.append((key, value))
    return true
  }

  func readString(key: String) -> String? {
    values[key]
  }

  func delete(key: String) -> Bool {
    values.removeValue(forKey: key)
    deleteCalls.append(key)
    return true
  }
}

func makeHTTPResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
  HTTPURLResponse(
    url: url,
    statusCode: statusCode,
    httpVersion: nil,
    headerFields: nil
  )!
}

/// UserDefaults that keeps values in memory and never touches disk.
///
/// A real suite is backed by `~/Library/Preferences/<suite>.plist`, and
/// `removePersistentDomain(forName:)` only empties that file. cfprefsd caches
/// the domain and rewrites the file later even after it is deleted, so a real
/// suite per test left an empty plist behind on every `swift test` run.
/// The typed getters and setters (`data(forKey:)`, `string(forKey:)`, `set(_:forKey:)`
/// with a Bool, and so on) route through the three overrides below, so no value
/// reaches cfprefsd. The unique suite name only keeps an unexpected
/// fall-through away from the real app's settings.
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Any] = [:]

  init() {
    super.init(suiteName: "SelectionBarCoreTests.InMemory.\(UUID().uuidString)")!
  }

  override func object(forKey defaultName: String) -> Any? {
    lock.withLock { values[defaultName] }
  }

  override func set(_ value: Any?, forKey defaultName: String) {
    lock.withLock { values[defaultName] = value }
  }

  override func removeObject(forKey defaultName: String) {
    lock.withLock { values[defaultName] = nil }
  }
}

@MainActor
func makeStore(keychain: InMemoryKeychain) -> SelectionBarSettingsStore {
  SelectionBarSettingsStore(
    defaults: InMemoryUserDefaults(),
    storageKey: "test.settings",
    keychain: keychain
  )
}
