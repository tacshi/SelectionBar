import AppKit
import Darwin
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
  typealias LoginShellCommandResolver = (String, String) -> URL?
  typealias AppleScriptRunner = (SelectionBarTerminalAppleScriptRequest) async throws -> Void
  typealias ProcessRunner = (SelectionBarTerminalProcessRequest) throws -> Void
  typealias FileWriter = (SelectionBarTerminalFileWriteRequest) throws -> Void
  typealias CleanupScheduler = ([URL]) -> Void

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
  ) -> Bool {
    guard runnableExecutableURL(from: text) != nil else { return false }
    guard let terminalApp else { return true }
    return appURL(for: terminalApp) != nil
  }

  func launchCommand(
    text: String,
    terminalApp: SelectionBarTerminalApp
  ) async throws {
    let plan = try makeLaunchPlan(text: text, terminalApp: terminalApp)

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
  ) throws -> SelectionBarTerminalLaunchPlan {
    let command = preparedCommandText(from: text)
    guard !command.isEmpty else {
      throw SelectionBarTerminalCommandServiceError.emptySelection
    }
    guard runnableExecutableURL(from: command) != nil else {
      throw SelectionBarTerminalCommandServiceError.commandNotRunnable
    }

    let homeDirectory = homeDirectoryProvider()
    guard let appURL = appURLResolver(terminalApp, homeDirectory) else {
      throw SelectionBarTerminalCommandServiceError.terminalUnavailable(terminalApp)
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
      return SelectionBarTerminalLaunchPlan(
        fileWrites: [
          SelectionBarTerminalFileWriteRequest(
            fileURL: configURL,
            contents: yaml
          )
        ],
        openURL: Self.warpLaunchURL(for: configURL),
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

  func runnableExecutableURL(from text: String) -> URL? {
    guard let token = firstRunnableToken(from: text) else { return nil }
    return resolveExecutable(token: token, environment: environmentProvider())
  }

  func firstRunnableToken(from text: String) -> String? {
    let firstLine = firstNonEmptyLine(in: text)
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
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func firstNonEmptyLine(in text: String) -> String {
    let trimmed = preparedCommandText(from: text)
    for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
      let candidate = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
      if !candidate.isEmpty {
        return candidate
      }
    }
    return ""
  }

  private func resolveExecutable(
    token: String,
    environment: [String: String]
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

    return loginShellCommandResolver(token, loginShellPath())
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

  private static func isExecutableFile(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return false
    }
    return FileManager.default.isExecutableFile(atPath: url.path)
  }

  private static func resolveExecutableInLoginShell(
    token: String,
    shellPath: String
  ) -> URL? {
    guard !token.isEmpty else { return nil }
    guard FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shellPath)
    process.arguments = ["-lc", "command -v -- \"$1\"", "selectionbar", token]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }

    process.waitUntilExit()
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

  private static func shellTokens(in line: String) -> [String] {
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

  private static func isEnvironmentAssignment(_ token: String) -> Bool {
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

  private static func pwShellPath() -> String? {
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

  static func runAppleScript(_ request: SelectionBarTerminalAppleScriptRequest) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-"] + request.arguments

    let inputPipe = Pipe()
    let errorPipe = Pipe()

    process.standardInput = inputPipe
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errorPipe

    do {
      try process.run()
    } catch {
      throw SelectionBarTerminalCommandServiceError.appleScriptFailed(error.localizedDescription)
    }

    if let data = request.source.data(using: .utf8) {
      inputPipe.fileHandleForWriting.write(data)
    }
    try? inputPipe.fileHandleForWriting.close()

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorText =
        String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "exit status \(process.terminationStatus)"
      throw SelectionBarTerminalCommandServiceError.appleScriptFailed(errorText)
    }
  }

  static func runProcess(_ request: SelectionBarTerminalProcessRequest) throws {
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

  static func writeFile(_ request: SelectionBarTerminalFileWriteRequest) throws {
    let directoryURL = request.fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try request.contents.write(to: request.fileURL, atomically: true, encoding: .utf8)
  }

  static func scheduleCleanup(for fileURLs: [URL]) {
    guard !fileURLs.isEmpty else { return }
    Task.detached(priority: .utility) {
      try? await Task.sleep(for: .seconds(30))
      for fileURL in fileURLs {
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

  private static let defaultPATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

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
