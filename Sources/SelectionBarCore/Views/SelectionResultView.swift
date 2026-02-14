import AppKit
import SwiftUI

/// Popup view that previews processed text and lets the user decide what to do with it.
struct SelectionResultView: View {
  let result: String
  let canApply: Bool
  let onDiscard: () -> Void
  let onCopy: (String) -> Void
  let onApply: () -> Void
  @State private var selectedText = ""

  var body: some View {
    VStack(alignment: .leading) {
      ResultTextView(text: result, selectedText: $selectedText)
        .frame(minWidth: 520, maxWidth: 520, minHeight: 140, maxHeight: 300)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.primary.opacity(0.05))
        )

      HStack {
        Button(String(localized: "Discard", bundle: .localizedModule), action: onDiscard)
        Spacer()
        Button(
          selectedText.isEmpty
            ? String(localized: "Copy", bundle: .localizedModule)
            : String(localized: "Copy Selected", bundle: .localizedModule)
        ) {
          onCopy(selectedText.isEmpty ? result : selectedText)
        }
        if canApply {
          Button(String(localized: "Apply", bundle: .localizedModule), action: onApply)
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
    )
  }
}

private struct ResultTextView: NSViewRepresentable {
  let text: String
  @Binding var selectedText: String

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true

    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.usesFindBar = false
    textView.drawsBackground = false
    textView.font = NSFont.preferredFont(forTextStyle: .body)
    textView.string = text
    textView.textContainerInset = NSSize(width: 12, height: 10)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width,
      height: .greatestFiniteMagnitude
    )
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }

    textView.textContainer?.containerSize = NSSize(
      width: nsView.contentSize.width,
      height: .greatestFiniteMagnitude
    )

    guard textView.string != text else { return }
    textView.string = text
    selectedText = ""
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    private var parent: ResultTextView

    init(parent: ResultTextView) {
      self.parent = parent
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      let selectionRange = textView.selectedRange()
      guard selectionRange.length > 0,
        let range = Range(selectionRange, in: textView.string)
      else {
        if !parent.selectedText.isEmpty {
          parent.selectedText = ""
        }
        return
      }

      let selected = String(textView.string[range])
      if parent.selectedText != selected {
        parent.selectedText = selected
      }
    }
  }
}
