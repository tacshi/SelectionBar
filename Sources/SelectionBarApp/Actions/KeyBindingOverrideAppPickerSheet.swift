import AppKit
import Foundation
import SelectionBarCore
import SwiftUI

struct KeyBindingOverrideAppIcon: View {
  let bundleID: String
  let size: CGFloat

  var body: some View {
    if let icon = resolveIcon() {
      Image(nsImage: icon)
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else {
      Image(systemName: "app")
        .foregroundStyle(.secondary)
    }
  }

  private func resolveIcon() -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icon.size = NSSize(width: size, height: size)
    return icon
  }
}

struct KeyBindingOverrideAppPickerSelection: Identifiable, Hashable {
  let bundleID: String
  let name: String

  var id: String { bundleID }
}

struct KeyBindingOverrideAppPickerSheet: View {
  let existingBundleIDs: Set<String>
  let onSelect: (KeyBindingOverrideAppPickerSelection) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""
  @State private var discoveredApps: [DiscoveredApp] = []
  @State private var selectedBundleID: String?

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
          guard let selectedBundleID else { return }
          guard let selected = discoveredApps.first(where: { $0.id == selectedBundleID }) else {
            return
          }
          onSelect(
            KeyBindingOverrideAppPickerSelection(
              bundleID: selected.id,
              name: selected.name
            )
          )
          dismiss()
        }
        .keyboardShortcut(.return)
        .disabled(selectedBundleID == nil)
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

      List(filteredApps, selection: $selectedBundleID) { app in
        HStack(spacing: 8) {
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
    .frame(width: 460, height: 500)
    .task {
      discoveredApps = await InstalledApplications.scan(excluding: existingBundleIDs)
    }
  }

}
