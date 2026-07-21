import AppKit
import Foundation

/// An installed application offered in one of the app-picker sheets.
struct DiscoveredApp: Identifiable {
  let id: String
  let name: String
  /// Optional to match the pickers' existing missing-icon fallback.
  let icon: NSImage?
}

/// Discovery of installed applications, shared by every app picker.
///
/// Both picker sheets previously carried their own byte-identical copy of this
/// scan, so a fix to one (a new search path, a different display-name fallback)
/// silently missed the other.
enum InstalledApplications {
  private static let searchPaths = [
    "/Applications",
    "/System/Applications",
    NSHomeDirectory().appending("/Applications"),
  ]

  /// An app found on disk, before its icon has been loaded. `Sendable` so the
  /// directory walk can happen off the main actor — `NSImage` is not.
  private struct AppEntry: Sendable {
    let bundleID: String
    let name: String
    let path: String
  }

  /// Scans the common application folders, skipping any bundle ID in
  /// `excluding` and de-duplicating apps that appear in more than one folder.
  /// Sorted by display name, case-insensitively.
  ///
  /// The directory walk reads an `Info.plist` for every installed app, which is
  /// far too slow to run on the main actor while a sheet is appearing; only the
  /// icon lookup stays on the main actor.
  @MainActor
  static func scan(excluding excludedBundleIDs: Set<String>) async -> [DiscoveredApp] {
    let entries = await Task.detached(priority: .userInitiated) {
      scanEntries(excluding: excludedBundleIDs)
    }.value

    return entries.map { entry in
      DiscoveredApp(
        id: entry.bundleID,
        name: entry.name,
        icon: NSWorkspace.shared.icon(forFile: entry.path)
      )
    }
  }

  private static func scanEntries(excluding excludedBundleIDs: Set<String>) -> [AppEntry] {
    var apps: [AppEntry] = []
    var seenBundleIDs = Set<String>()

    for searchPath in searchPaths {
      let url = URL(filePath: searchPath)
      guard
        let contents = try? FileManager.default.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: nil
        )
      else {
        continue
      }

      for itemURL in contents where itemURL.pathExtension == "app" {
        guard let bundle = Bundle(url: itemURL),
          let bundleID = bundle.bundleIdentifier,
          !excludedBundleIDs.contains(bundleID),
          !seenBundleIDs.contains(bundleID)
        else {
          continue
        }

        seenBundleIDs.insert(bundleID)

        let name =
          bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
          ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
          ?? itemURL.deletingPathExtension().lastPathComponent
        apps.append(AppEntry(bundleID: bundleID, name: name, path: itemURL.path))
      }
    }

    return apps.sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}
