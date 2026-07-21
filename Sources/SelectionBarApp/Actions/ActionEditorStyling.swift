import SwiftUI

private struct ActionEditorTextBoxStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
      .clipShape(.rect(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75), lineWidth: 1.5)
      }
  }
}

extension View {
  func actionEditorTextBox() -> some View {
    modifier(ActionEditorTextBoxStyle())
  }
}

struct ActionEditorSection<Content: View>: View {
  let title: LocalizedStringKey?
  let content: Content

  init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title)
          .font(.headline)
          .foregroundStyle(.secondary)
      }

      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ActionEditorRow<Content: View>: View {
  let title: LocalizedStringKey
  let content: Content

  init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
      Spacer(minLength: 16)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
