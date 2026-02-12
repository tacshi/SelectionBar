import Foundation
import Security

public protocol KeychainServiceProtocol: Sendable {
  func save(key: String, value: String) -> Bool
  func readString(key: String) -> String?
  func delete(key: String) -> Bool
}

/// Keychain-only API key storage for SelectionBar.
public final class KeychainHelper: KeychainServiceProtocol, @unchecked Sendable {
  public static let shared = KeychainHelper()

  private let keychainService = "com.selectionbar.apikeys"

  private init() {}

  public func save(key: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }

    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    return status == errSecSuccess
  }

  public func readString(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func delete(key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
