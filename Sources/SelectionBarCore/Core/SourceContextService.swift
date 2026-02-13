import ApplicationServices
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "SourceContextService")

enum SourceContextService {
  /// Resolves the source context (browser URL, document file path, or Finder selection).
  /// Tries browser URL first, then AX document path, then app-specific AppleScript.
  nonisolated static func resolveSource(bundleID: String?, pid: pid_t?) async -> String? {
    // Try browser URL first
    if let bundleID, let url = await browserURL(for: bundleID) {
      return url
    }

    // Try document path via Accessibility API
    if let pid, let path = documentPath(for: pid) {
      return path
    }

    // Try app-specific fallbacks (e.g. Finder selection for Quick Look)
    if let bundleID, let path = await appSpecificSource(for: bundleID) {
      return path
    }

    return nil
  }

  // MARK: - Browser URL (AppleScript)

  private enum BrowserKind {
    case safari
    case chromium
  }

  private static let browserKinds: [String: BrowserKind] = [
    // Safari
    "com.apple.Safari": .safari,
    "com.apple.SafariTechnologyPreview": .safari,
    // Chrome
    "com.google.Chrome": .chromium,
    "com.google.Chrome.beta": .chromium,
    "com.google.Chrome.dev": .chromium,
    "com.google.Chrome.canary": .chromium,
    // Chromium
    "org.chromium.Chromium": .chromium,
    // Arc
    "company.thebrowser.Browser": .chromium,
    // Edge
    "com.microsoft.edgemac": .chromium,
    "com.microsoft.edgemac.Dev": .chromium,
    "com.microsoft.edgemac.Beta": .chromium,
    "com.microsoft.edgemac.Canary": .chromium,
    // Brave
    "com.brave.Browser": .chromium,
    "com.brave.Browser.beta": .chromium,
    "com.brave.Browser.nightly": .chromium,
    // Opera
    "com.operasoftware.Opera": .chromium,
    "com.operasoftware.OperaGX": .chromium,
    // Vivaldi
    "com.vivaldi.Vivaldi": .chromium,
    // Yandex
    "ru.yandex.desktop.yandex-browser": .chromium,
    // Naver Whale
    "com.naver.Whale": .chromium,
    // SigmaOS
    "com.nickvision.nickvision-browser": .chromium,
    // Orion (WebKit-based but supports Chromium AppleScript pattern)
    "com.kagi.kagimacOS": .chromium,
  ]

  private nonisolated static func browserURL(for bundleID: String) async -> String? {
    guard let kind = browserKinds[bundleID] else {
      return nil
    }

    let script: String
    switch kind {
    case .safari:
      script = "tell application \"Safari\" to return URL of front document"
    case .chromium:
      script =
        "tell application id \"\(bundleID)\" to return URL of active tab of first window"
    }

    let result = await runAppleScript(script)
    if result == nil {
      logger.warning(
        "Failed to get URL from browser \(bundleID, privacy: .public). Check Automation permission in System Settings > Privacy & Security > Automation."
      )
    }
    return result
  }

  private nonisolated static func runAppleScript(_ source: String) async -> String? {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
          logger.debug(
            "AppleScript error: \(error[NSAppleScript.errorMessage] as? String ?? "unknown", privacy: .public)"
          )
        }
        continuation.resume(returning: result?.stringValue)
      }
    }
  }

  // MARK: - App-specific source (AppleScript)

  /// Fallback for apps that don't expose AX document attributes.
  /// Uses AppleScript to get the current selection or document path.
  private nonisolated static func appSpecificSource(for bundleID: String) async -> String? {
    let script: String?
    switch bundleID {
    case "com.apple.finder":
      // Finder: get the selected file path (works for Quick Look / Space preview)
      script = """
        tell application "Finder"
          set theSelection to selection
          if (count of theSelection) > 0 then
            return POSIX path of (item 1 of theSelection as alias)
          end if
        end tell
        """
    default:
      script = nil
    }

    guard let script else { return nil }
    return await runAppleScript(script)
  }

  // MARK: - Document path (Accessibility API)

  /// Returns the file path of the frontmost window's document using the AX API.
  /// Works with apps that expose kAXDocumentAttribute (TextEdit, Xcode, VS Code, etc.).
  private nonisolated static func documentPath(for pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)

    var focusedWindow: CFTypeRef?
    let windowResult = AXUIElementCopyAttributeValue(
      app, kAXFocusedWindowAttribute as CFString, &focusedWindow)
    guard windowResult == .success else {
      logger.debug("AX: could not get focused window, error: \(windowResult.rawValue)")
      return nil
    }

    var documentValue: CFTypeRef?
    let docResult = AXUIElementCopyAttributeValue(
      focusedWindow as! AXUIElement, kAXDocumentAttribute as CFString, &documentValue)
    guard docResult == .success else {
      logger.debug("AX: no document attribute on focused window, error: \(docResult.rawValue)")
      return nil
    }

    guard let urlString = documentValue as? String else { return nil }

    // kAXDocumentAttribute returns a file URL string like "file:///path/to/file"
    if let url = URL(string: urlString), url.isFileURL {
      let path = url.path
      // Skip directories (e.g. terminals report cwd, not a document)
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
        logger.debug("AX: document attribute is a directory, skipping: \(path, privacy: .public)")
        return nil
      }
      return path
    }
    return urlString
  }
}
