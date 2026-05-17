import AppKit
import SelectionBarCore
import SwiftUI

struct ApplicationPickerSheet: View {
  let existingBundleIDs: Set<String>
  var selectionLimit: Int? = nil
  let onAppsSelected: ([IgnoredApp]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""
  @State private var discoveredApps: [DiscoveredApp] = []
  @State private var selectedBundleIDs: Set<String> = []

  private struct DiscoveredApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
  }

  private var filteredApps: [DiscoveredApp] {
    if searchText.isEmpty {
      return discoveredApps
    }
    return discoveredApps.filter {
      $0.name.localizedStandardContains(searchText)
        || $0.id.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.escape)
        Spacer()
        Text("Choose Applications")
          .font(.headline)
        Spacer()
        Button("Add") {
          let apps = discoveredApps.filter { selectedBundleIDs.contains($0.id) }
            .map { IgnoredApp(id: $0.id, name: $0.name) }
          onAppsSelected(apps)
          dismiss()
        }
        .keyboardShortcut(.return)
        .disabled(selectedBundleIDs.isEmpty)
      }
      .padding()

      Divider()

      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search", text: $searchText)
          .textFieldStyle(.plain)
      }
      .padding(8)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(.rect(cornerRadius: 8))
      .padding(.horizontal)
      .padding(.top, 8)

      List(filteredApps, selection: $selectedBundleIDs) { app in
        HStack {
          if let icon = app.icon {
            Image(nsImage: icon)
              .resizable()
              .frame(width: 24, height: 24)
          } else {
            Image(systemName: "app")
              .frame(width: 24, height: 24)
          }
          VStack(alignment: .leading, spacing: 1) {
            Text(app.name)
            Text(app.id)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .tag(app.id)
      }
      .listStyle(.bordered)
    }
    .frame(width: 420, height: 450)
    .onAppear {
      discoveredApps = scanApplications()
    }
    .onChange(of: selectedBundleIDs) { oldValue, newValue in
      guard let selectionLimit, newValue.count > selectionLimit else { return }
      let newest = newValue.subtracting(oldValue)
      selectedBundleIDs = Set(newest.prefix(selectionLimit))
    }
  }

  /// Scan common app folders for .app bundles.
  private func scanApplications() -> [DiscoveredApp] {
    var apps: [DiscoveredApp] = []
    var seenBundleIDs = Set<String>()

    let searchPaths = [
      "/Applications",
      "/System/Applications",
      NSHomeDirectory().appending("/Applications"),
    ]

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
          !existingBundleIDs.contains(bundleID),
          !seenBundleIDs.contains(bundleID)
        else {
          continue
        }

        seenBundleIDs.insert(bundleID)

        let name =
          bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
          ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
          ?? itemURL.deletingPathExtension().lastPathComponent

        let icon = NSWorkspace.shared.icon(forFile: itemURL.path)
        apps.append(DiscoveredApp(id: bundleID, name: name, icon: icon))
      }
    }

    return apps.sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}
