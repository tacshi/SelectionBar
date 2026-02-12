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

@MainActor
func makeStore(
  defaultsSuite: String = "SelectionBarCoreTests.\(UUID().uuidString)",
  keychain: InMemoryKeychain
) -> SelectionBarSettingsStore {
  let defaults = UserDefaults(suiteName: defaultsSuite)!
  defaults.removePersistentDomain(forName: defaultsSuite)
  return SelectionBarSettingsStore(
    defaults: defaults,
    storageKey: "test.settings",
    keychain: keychain
  )
}
