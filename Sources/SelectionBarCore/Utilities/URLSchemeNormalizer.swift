import Foundation

/// Normalizes a raw string into a valid URL scheme, stripping `://` or trailing colons
/// and validating that only RFC 3986 scheme characters remain.
func normalizedURLScheme(_ raw: String) -> String? {
  var scheme = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if let separator = scheme.range(of: "://") {
    scheme = String(scheme[..<separator.lowerBound])
  }
  if scheme.hasSuffix(":") {
    scheme.removeLast()
  }
  guard !scheme.isEmpty else { return nil }
  let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
  let isValid = scheme.unicodeScalars.allSatisfy { allowed.contains($0) }
  return isValid ? scheme : nil
}
