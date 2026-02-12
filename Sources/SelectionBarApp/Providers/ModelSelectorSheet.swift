import SwiftUI

/// Searchable modal selector for model IDs.
struct ModelSelectorSheet: View {
  let models: [String]
  @Binding var selectedModel: String
  var title = "Select Model"
  var showClearOption = false
  var clearOptionLabel = "Clear Selection"
  var width: CGFloat = 450
  var height: CGFloat = 500

  @State private var searchText = ""
  @Environment(\.dismiss) private var dismiss

  private var filteredModels: [String] {
    if searchText.isEmpty {
      return models
    }
    return models.filter { $0.localizedStandardContains(searchText) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.escape, modifiers: [])
      }
      .padding()

      TextField("Search models...", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)

      Divider()
        .padding(.top)

      List {
        if showClearOption {
          Button {
            selectedModel = ""
            dismiss()
          } label: {
            HStack {
              Text(clearOptionLabel)
                .foregroundStyle(.secondary)
              Spacer()
              if selectedModel.isEmpty {
                Image(systemName: "checkmark")
                  .foregroundStyle(.blue)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }

        ForEach(filteredModels, id: \.self) { model in
          Button {
            selectedModel = model
            dismiss()
          } label: {
            HStack {
              Text(model)
                .font(.system(.body, design: .monospaced))
              Spacer()
              if model == selectedModel {
                Image(systemName: "checkmark")
                  .foregroundStyle(.blue)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .listStyle(.plain)

      Divider()
      HStack {
        if filteredModels.count != models.count {
          Text("\(filteredModels.count) of \(models.count) models", comment: "Filtered model count")
        } else {
          Text("\(models.count) models", comment: "Total model count")
        }
        Spacer()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding()
    }
    .frame(width: width, height: height)
  }
}
