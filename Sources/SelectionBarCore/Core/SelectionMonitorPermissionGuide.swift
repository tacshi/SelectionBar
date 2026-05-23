import AppKit
import PermissionFlow

@MainActor
public final class SelectionBarPermissionGuide {
  private let panelController = SelectionBarPermissionPanelController()

  public init() {}

  public func requestAccessibilityPermission() {
    requestPermission(for: .accessibility)
  }

  public func requestInputMonitoringPermission() {
    requestPermission(for: .inputMonitoring)
  }

  private func requestPermission(for pane: PermissionFlowPane) {
    NSWorkspace.shared.open(pane.settingsURL)
    panelController.show(
      pane: pane,
      appURL: Self.currentAppBundleURL
    )
  }

  private static var currentAppBundleURL: URL? {
    let bundleURL = Bundle.main.bundleURL.standardizedFileURL
    guard bundleURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else {
      return nil
    }
    return bundleURL
  }
}

@MainActor
protocol SelectionMonitorPermissionGuiding: AnyObject {
  func requestAccessibilityPermission()
  func requestInputMonitoringPermission()
}

@MainActor
extension SelectionBarPermissionGuide: SelectionMonitorPermissionGuiding {}

@MainActor
final class NoopSelectionMonitorPermissionGuide: SelectionMonitorPermissionGuiding {
  func requestAccessibilityPermission() {}
  func requestInputMonitoringPermission() {}
}
