import Darwin
import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarTerminalCommandService Tests")
@MainActor
struct SelectionBarTerminalCommandServiceTests {
  @Test("detection skips env assignments and resolves PATH executables")
  func detectionSkipsEnvironmentAssignments() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let service = makeService(pathEntries: [tempDirectory.path], homeDirectory: tempDirectory)

    #expect(service.firstRunnableToken(from: "FOO=1 BAR=2 git status") == "git")
    let canRunCommand = await service.canRunCommand(text: "FOO=1 BAR=2 git status")
    #expect(canRunCommand)
  }

  @Test("detection rejects shell builtins relative paths and empty input")
  func detectionRejectsBuiltinsRelativePathsAndEmptyInput() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let service = makeService(pathEntries: [tempDirectory.path], homeDirectory: tempDirectory)

    let rejectsBuiltin = await service.canRunCommand(text: "cd /tmp")
    let rejectsRelativeScript = await service.canRunCommand(text: "./script.sh")
    let rejectsRelativePath = await service.canRunCommand(text: "scripts/run")
    let rejectsWhitespace = await service.canRunCommand(text: "   ")

    #expect(!rejectsBuiltin)
    #expect(!rejectsRelativeScript)
    #expect(!rejectsRelativePath)
    #expect(!rejectsWhitespace)
  }

  @Test("detection accepts absolute executable paths")
  func detectionAcceptsAbsoluteExecutablePaths() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let executableURL = try makeExecutable(named: "custom-tool", in: tempDirectory)
    let service = makeService(pathEntries: [], homeDirectory: tempDirectory)

    let canRunCommand = await service.canRunCommand(text: "\(executableURL.path) --version")
    #expect(canRunCommand)
  }

  @Test("detection falls back to login shell command resolution for user-installed tools")
  func detectionFallsBackToLoginShellResolution() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let bunURL = try makeExecutable(named: "bun", in: tempDirectory)
    let service = makeService(
      pathEntries: [],
      homeDirectory: tempDirectory,
      loginShellCommandResolver: { token, _ in
        token == "bun" ? bunURL : nil
      }
    )

    #expect(service.firstRunnableToken(from: "bun create next-app@latest my-app --yes") == "bun")
    let canRunCommand = await service.canRunCommand(text: "bun create next-app@latest my-app --yes")
    #expect(canRunCommand)
  }

  @Test("multi-line selection uses first runnable line and preserves full command in launch plan")
  func multilineSelectionDetectionAndLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = try makeAppBundle(
      named: "Alacritty", executableNames: ["alacritty"], in: tempDirectory)
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.alacritty: appURL]
    )

    let input = "\n\nFOO=1 git status\nprintf 'done'\n"
    let plan = try await service.makeLaunchPlan(text: input, terminalApp: .alacritty)

    #expect(service.firstRunnableToken(from: input) == "git")
    #expect(plan.processRequest?.arguments.last == "FOO=1 git status\nprintf 'done'")
  }

  @Test("terminal launch plan uses AppleScript do script with command argument")
  func terminalAppleScriptLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = tempDirectory.appendingPathComponent("Terminal.app")
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.terminal: appURL]
    )

    let plan = try await service.makeLaunchPlan(text: "git status", terminalApp: .terminal)
    let source = plan.appleScriptRequest?.source ?? ""

    #expect(source.contains("do script theCommand in front window"))
    #expect(source.contains("do script theCommand\n        activate"))
    #expect(plan.appleScriptRequest?.arguments == ["git status"])
    #expect(plan.processRequest == nil)
  }

  @Test("iTerm2 launch plan prefers new tabs in an existing window")
  func iTerm2AppleScriptLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = tempDirectory.appendingPathComponent("iTerm.app")
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.iterm2: appURL]
    )

    let plan = try await service.makeLaunchPlan(text: "git status", terminalApp: .iterm2)
    let source = plan.appleScriptRequest?.source ?? ""

    #expect(source.contains("create tab with default profile command theCommand"))
    #expect(
      source.contains("create window with default profile command theCommand\n        activate"))
  }

  @Test("ghostty launch plan prefers new tabs in an existing window")
  func ghosttyAppleScriptLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = tempDirectory.appendingPathComponent("Ghostty.app")
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.ghostty: appURL]
    )

    let plan = try await service.makeLaunchPlan(text: "git status", terminalApp: .ghostty)
    let source = plan.appleScriptRequest?.source ?? ""

    #expect(source.contains("new tab in front window with configuration cfg"))
    #expect(source.contains("new window with configuration cfg\n        activate"))
  }

  @Test("warp launch plan writes temporary config and opens launch URI")
  func warpLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = tempDirectory.appendingPathComponent("Warp.app")
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.warp: appURL]
    )

    let plan = try await service.makeLaunchPlan(text: "git status", terminalApp: .warp)

    #expect(plan.fileWrites.count == 1)
    #expect(
      plan.fileWrites[0].fileURL.path.contains(
        ".warp/launch_configurations/selectionbar-run-command-")
    )
    #expect(plan.fileWrites[0].contents.contains("cwd: \"\(tempDirectory.path)\""))
    #expect(plan.fileWrites[0].contents.contains("exec: |"))
    #expect(plan.fileWrites[0].contents.contains("-lc 'git status'"))
    #expect(plan.openURL?.absoluteString.hasPrefix("warp://launch/") == true)
    #expect(plan.cleanupURLs == [plan.fileWrites[0].fileURL])
  }

  @Test("kitty launch plan uses embedded executable and home directory")
  func kittyLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = try makeAppBundle(named: "kitty", executableNames: ["kitty"], in: tempDirectory)
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.kitty: appURL]
    )

    let plan = try await service.makeLaunchPlan(text: "git status", terminalApp: .kitty)

    #expect(plan.processRequest?.executableURL.lastPathComponent == "kitty")
    #expect(
      plan.processRequest?.arguments.prefix(3) == ["--hold", "--directory", tempDirectory.path])
  }

  @Test("wezterm launch plan prefers embedded wezterm CLI")
  func wezTermLaunchPlan() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)
    let appURL = try makeAppBundle(
      named: "WezTerm",
      executableNames: ["wezterm", "wezterm-gui"],
      in: tempDirectory
    )
    let service = makeService(
      pathEntries: [tempDirectory.path],
      homeDirectory: tempDirectory,
      appURLs: [.wezterm: appURL]
    )

    let plan = try await service.makeLaunchPlan(text: "git status", terminalApp: .wezterm)

    #expect(plan.processRequest?.executableURL.lastPathComponent == "wezterm")
    #expect(plan.processRequest?.arguments.prefix(3) == ["start", "--cwd", tempDirectory.path])
  }

  @Test("launchCommand routes AppleScript requests without opening a real terminal")
  func launchCommandRoutesAppleScriptRequest() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)

    var capturedRequest: SelectionBarTerminalAppleScriptRequest?
    let service = SelectionBarTerminalCommandService(
      homeDirectoryProvider: { tempDirectory },
      environmentProvider: { ["PATH": tempDirectory.path] },
      appURLResolver: { app, _ in
        app == .terminal ? tempDirectory.appendingPathComponent("Terminal.app") : nil
      },
      appleScriptRunner: { request in
        capturedRequest = request
      }
    )

    try await service.launchCommand(text: "git status", terminalApp: .terminal)

    #expect(capturedRequest?.arguments == ["git status"])
    #expect(capturedRequest?.source.contains("tell application \"Terminal\"") == true)
  }

  @Test("launchCommand writes opens and schedules cleanup for warp")
  func launchCommandRoutesWarpArtifacts() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    _ = try makeExecutable(named: "git", in: tempDirectory)

    var writes: [SelectionBarTerminalFileWriteRequest] = []
    var openedURLs: [URL] = []
    var cleanedURLs: [URL] = []

    let service = SelectionBarTerminalCommandService(
      homeDirectoryProvider: { tempDirectory },
      environmentProvider: { ["PATH": tempDirectory.path] },
      appURLResolver: { app, _ in
        app == .warp ? tempDirectory.appendingPathComponent("Warp.app") : nil
      },
      fileWriter: { request in
        writes.append(request)
      },
      urlOpener: { url in
        openedURLs.append(url)
        return true
      },
      cleanupScheduler: { urls in
        cleanedURLs = urls
      }
    )

    try await service.launchCommand(text: "git status", terminalApp: .warp)

    #expect(writes.count == 1)
    #expect(openedURLs.count == 1)
    #expect(cleanedURLs == [writes[0].fileURL])
  }

  private func makeService(
    pathEntries: [String],
    homeDirectory: URL,
    appURLs: [SelectionBarTerminalApp: URL] = [:],
    loginShellCommandResolver: SelectionBarTerminalCommandService.LoginShellCommandResolver? = nil
  ) -> SelectionBarTerminalCommandService {
    SelectionBarTerminalCommandService(
      homeDirectoryProvider: { homeDirectory },
      environmentProvider: {
        if pathEntries.isEmpty {
          return [:]
        }
        return ["PATH": pathEntries.joined(separator: ":")]
      },
      appURLResolver: { app, _ in
        appURLs[app]
      },
      loginShellCommandResolver: loginShellCommandResolver
        ?? { _, _ in nil }
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("selectionbar-terminal-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @discardableResult
  private func makeAppBundle(
    named name: String,
    executableNames: [String],
    in directory: URL
  ) throws -> URL {
    let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
    let macOSDirectory =
      appURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOSDirectory, withIntermediateDirectories: true)

    for executableName in executableNames {
      _ = try makeExecutable(named: executableName, in: macOSDirectory)
    }

    return appURL
  }

  @discardableResult
  private func makeExecutable(named name: String, in directory: URL) throws -> URL {
    let executableURL = directory.appendingPathComponent(name)
    let contents = "#!/bin/sh\nexit 0\n"
    try contents.write(to: executableURL, atomically: true, encoding: .utf8)
    let result = executableURL.path.withCString { path in
      chmod(path, mode_t(0o755))
    }
    #expect(result == 0)
    return executableURL
  }
}
