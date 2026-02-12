import Foundation
import ServiceManagement

/// Manages launch at login functionality using SMAppService (macOS 13+).
public enum LaunchAtLoginManager {

  private static var isRunningTests: Bool {
    let processName = ProcessInfo.processInfo.processName.lowercased()
    return processName.contains("xctest")
      || processName.contains("swiftpm-testing")
      || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  public static func enable() throws {
    guard !isRunningTests else { return }
    try SMAppService.mainApp.register()
  }

  public static func disable() throws {
    guard !isRunningTests else { return }
    try SMAppService.mainApp.unregister()
  }

  public static var isEnabled: Bool {
    guard !isRunningTests else { return false }
    return SMAppService.mainApp.status == .enabled
  }
}
