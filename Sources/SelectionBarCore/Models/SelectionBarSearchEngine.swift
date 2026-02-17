import Foundation

/// Web search engine target for the Selection Bar search action.
public enum SelectionBarSearchEngine: String, CaseIterable, Codable, Sendable {
  case google = "google"
  case baidu = "baidu"
  case bing = "bing"
  case sogou = "sogou"
  case so360 = "so360"
  case yandex = "yandex"
  case duckDuckGo = "duckduckgo"
  case custom = "custom"

  public func searchURL(for query: String) -> URL? {
    searchURLCandidates(for: query).first
  }

  public func searchURLCandidates(
    for query: String,
    customConfiguration: String = ""
  ) -> [URL] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return [] }

    if self == .custom {
      return Self.customSearchURLCandidates(for: trimmedQuery, configuration: customConfiguration)
    }

    guard let url = builtInSearchURL(for: trimmedQuery) else { return [] }
    return [url]
  }

  public func isConfigurationValid(customConfiguration: String = "") -> Bool {
    guard self == .custom else { return true }
    return Self.isValidCustomConfiguration(customConfiguration)
  }

  private func builtInSearchURL(for query: String) -> URL? {
    guard self != .custom else { return nil }

    var components: URLComponents?

    switch self {
    case .google:
      components = URLComponents(string: "https://www.google.com/search")
      components?.queryItems = [URLQueryItem(name: "q", value: query)]
    case .baidu:
      components = URLComponents(string: "https://www.baidu.com/s")
      components?.queryItems = [URLQueryItem(name: "wd", value: query)]
    case .bing:
      components = URLComponents(string: "https://www.bing.com/search")
      components?.queryItems = [URLQueryItem(name: "q", value: query)]
    case .sogou:
      components = URLComponents(string: "https://www.sogou.com/web")
      components?.queryItems = [URLQueryItem(name: "query", value: query)]
    case .so360:
      components = URLComponents(string: "https://www.so.com/s")
      components?.queryItems = [URLQueryItem(name: "q", value: query)]
    case .yandex:
      components = URLComponents(string: "https://yandex.com/search/")
      components?.queryItems = [URLQueryItem(name: "text", value: query)]
    case .duckDuckGo:
      components = URLComponents(string: "https://duckduckgo.com/")
      components?.queryItems = [URLQueryItem(name: "q", value: query)]
    case .custom:
      return nil
    }

    return components?.url
  }

  private static func customSearchURLCandidates(
    for query: String,
    configuration: String
  ) -> [URL] {
    let raw = configuration.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return [] }

    guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      return []
    }

    if raw.contains("{{query}}") {
      let candidate = raw.replacingOccurrences(of: "{{query}}", with: encodedQuery)
      guard let url = URL(string: candidate), url.scheme != nil else { return [] }
      return [url]
    }

    guard let scheme = normalizedURLScheme(raw) else { return [] }
    let candidates = [
      "\(scheme)://search?query=\(encodedQuery)",
      "\(scheme)://search?q=\(encodedQuery)",
      "\(scheme)://lookup?word=\(encodedQuery)",
      "\(scheme)://dict?word=\(encodedQuery)",
      "\(scheme)://\(encodedQuery)",
    ]
    return candidates.compactMap(URL.init(string:))
  }

  private static func isValidCustomConfiguration(_ configuration: String) -> Bool {
    let raw = configuration.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return false }

    if raw.contains("{{query}}") {
      let probe = raw.replacingOccurrences(of: "{{query}}", with: "test")
      guard let url = URL(string: probe),
        let scheme = url.scheme,
        !scheme.isEmpty
      else {
        return false
      }
      if scheme == "http" || scheme == "https" {
        return url.host?.isEmpty == false
      }
      return true
    }

    return normalizedURLScheme(raw) != nil
  }

}
