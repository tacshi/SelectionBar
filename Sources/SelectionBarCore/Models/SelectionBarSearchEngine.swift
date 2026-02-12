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

  public func searchURL(for query: String) -> URL? {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return nil }

    var components: URLComponents?

    switch self {
    case .google:
      components = URLComponents(string: "https://www.google.com/search")
      components?.queryItems = [URLQueryItem(name: "q", value: trimmedQuery)]
    case .baidu:
      components = URLComponents(string: "https://www.baidu.com/s")
      components?.queryItems = [URLQueryItem(name: "wd", value: trimmedQuery)]
    case .bing:
      components = URLComponents(string: "https://www.bing.com/search")
      components?.queryItems = [URLQueryItem(name: "q", value: trimmedQuery)]
    case .sogou:
      components = URLComponents(string: "https://www.sogou.com/web")
      components?.queryItems = [URLQueryItem(name: "query", value: trimmedQuery)]
    case .so360:
      components = URLComponents(string: "https://www.so.com/s")
      components?.queryItems = [URLQueryItem(name: "q", value: trimmedQuery)]
    case .yandex:
      components = URLComponents(string: "https://yandex.com/search/")
      components?.queryItems = [URLQueryItem(name: "text", value: trimmedQuery)]
    case .duckDuckGo:
      components = URLComponents(string: "https://duckduckgo.com/")
      components?.queryItems = [URLQueryItem(name: "q", value: trimmedQuery)]
    }

    return components?.url
  }
}
