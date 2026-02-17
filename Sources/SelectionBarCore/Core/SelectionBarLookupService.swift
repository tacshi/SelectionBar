import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "SelectionBarLookupService")

@MainActor
struct SelectionBarLookupService {
  @discardableResult
  func translateWithApp(text: String, providerId: String) async -> Bool {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return false }
    guard let appProvider = SelectionBarTranslationAppProvider(rawValue: providerId) else {
      return false
    }
    return await openTranslationApp(provider: appProvider, query: query)
  }

  @discardableResult
  func lookUp(text: String, settings: SelectionBarSettingsStore) -> Bool {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      logger.notice("Look up skipped: empty query")
      return false
    }

    let provider = settings.selectionBarLookupProvider
    logger.notice(
      "Look up requested. provider=\(provider.rawValue, privacy: .public), query=\(self.queryPreview(query), privacy: .public)"
    )

    let success: Bool
    switch provider {
    case .systemDictionary:
      success = openSystemDictionary(query: query)
    case .eudic:
      success = openEudic(query: query)
    case .customApp:
      success = openCustomLookupScheme(
        query: query,
        configuredScheme: settings.selectionBarLookupCustomScheme
      )
    }

    logger.notice(
      "Look up completed. provider=\(provider.rawValue, privacy: .public), success=\(success, privacy: .public)"
    )

    return success
  }

  func urlToOpen(text: String) -> URL? {
    normalizedWebURL(from: text)
  }

  @discardableResult
  func openURL(text: String) -> Bool {
    guard let url = normalizedWebURL(from: text) else { return false }
    return NSWorkspace.shared.open(url)
  }

  private func normalizedWebURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let directURL = URL(string: trimmed),
      let scheme = directURL.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = directURL.host,
      !host.isEmpty
    {
      return directURL
    }

    guard !trimmed.localizedStandardContains(" ") else { return nil }
    guard let inferredURL = URL(string: "https://\(trimmed)"),
      let host = inferredURL.host,
      !host.isEmpty
    else {
      return nil
    }

    if host.firstIndex(of: ".") != nil || host.caseInsensitiveCompare("localhost") == .orderedSame {
      return inferredURL
    }
    return nil
  }

  private func openSystemDictionary(query: String) -> Bool {
    guard
      let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: "dict://\(encoded)")
    else {
      logger.notice("System Dictionary lookup failed: unable to encode URL")
      return false
    }

    let opened = NSWorkspace.shared.open(url)
    logger.notice("System Dictionary open result: \(opened, privacy: .public)")
    return opened
  }

  private func openEudic(query: String) -> Bool {
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
      logger.notice("Eudic lookup failed: unable to encode query")
      return false
    }

    let candidates = [
      "eudic://dict/\(encoded)",
      "eudic://dict?word=\(encoded)",
      "eudic://\(encoded)",
    ]

    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      if NSWorkspace.shared.open(url) {
        return true
      }
    }

    return false
  }

  private func openCustomLookupScheme(query: String, configuredScheme: String) -> Bool {
    let raw = configuredScheme.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      logger.notice("Custom lookup failed: URL scheme is empty")
      return false
    }

    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
      logger.notice("Custom lookup failed: unable to encode query")
      return false
    }

    if raw.localizedStandardContains("{{query}}") {
      let templateCandidate = raw.replacing("{{query}}", with: encoded)
      logger.notice("Custom lookup using URL template")
      return openURLCandidates([templateCandidate])
    }

    guard let scheme = normalizedURLScheme(raw) else {
      logger.notice("Custom lookup failed: invalid URL scheme input")
      return false
    }

    let candidates = [
      "\(scheme)://lookup?word=\(encoded)",
      "\(scheme)://dict?word=\(encoded)",
      "\(scheme)://search?query=\(encoded)",
      "\(scheme)://word?text=\(encoded)",
      "\(scheme)://\(encoded)",
    ]

    logger.notice("Custom lookup using scheme=\(scheme, privacy: .public)")
    return openURLCandidates(candidates)
  }

  private func openTranslationApp(
    provider: SelectionBarTranslationAppProvider,
    query: String
  ) async -> Bool {
    if provider == .bob {
      return await openBobInstantTranslate(query: query)
    }

    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
      return false
    }

    let candidates = provider.translationURLCandidates(encodedQuery: encoded)
    guard !candidates.isEmpty else {
      logger.notice(
        "Translate app open skipped: no registered URL scheme path for provider=\(provider.rawValue, privacy: .public)"
      )
      return false
    }

    return openURLCandidates(candidates)
  }

  private func openBobInstantTranslate(query: String) async -> Bool {
    copyToClipboard(query)

    let bundleID =
      SelectionBarTranslationAppProvider.bob.bundleIDs.first {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
      } ?? SelectionBarTranslationAppProvider.bob.bundleIDs[0]

    let (success, errorMessage) = await Self.runBobOsascript(bundleID: bundleID)

    if success {
      logger.debug("Invoked Bob pasteboard translate via osascript")
    } else if let errorMessage {
      logger.debug("Bob osascript failed: \(errorMessage, privacy: .public)")
    }

    return success
  }

  private func openURLCandidates(_ candidates: [String]) -> Bool {
    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      let opened = NSWorkspace.shared.open(url)
      logger.debug(
        "Tried URL candidate: \(candidate, privacy: .public), opened=\(opened, privacy: .public)"
      )
      if opened {
        return true
      }
    }

    logger.debug("All URL candidates failed")
    return false
  }

  private func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  private func queryPreview(_ query: String, maxLength: Int = 80) -> String {
    if query.count <= maxLength {
      return query
    }
    return String(query.prefix(maxLength)) + "..."
  }

  /// Runs Bob AppleScript in a subprocess off the main actor.
  /// Returns `(success, errorMessage)`.
  private nonisolated static func runBobOsascript(
    bundleID: String
  ) async -> (Bool, String?) {
    let script = """
      use scripting additions
      use framework "Foundation"
      on callBob(recordValue)
        set theParameter to (((current application's NSString)'s alloc)'s initWithData:((current application's NSJSONSerialization)'s dataWithJSONObject:recordValue options:1 |error|:(missing value)) encoding:4) as string
        tell application id "\(bundleID)" to request theParameter
      end callBob
      callBob({|path|:"translate", body:{action:"pasteboardTranslate"}})
      """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      if process.terminationStatus == 0 {
        return (true, nil)
      }

      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      if let errorText = String(data: errorData, encoding: .utf8), !errorText.isEmpty {
        return (false, errorText)
      }

      return (false, "exit status \(process.terminationStatus)")
    } catch {
      return (false, error.localizedDescription)
    }
  }
}
