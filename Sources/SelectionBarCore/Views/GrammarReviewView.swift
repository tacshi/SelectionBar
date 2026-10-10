import AppKit
import SwiftUI

struct GrammarIndicatorView: View {
  let count: Int
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      Label("\(count)", systemImage: "text.badge.checkmark").padding(6)
    }
    .buttonStyle(.plain)
    .background(.regularMaterial, in: Capsule())
    .help(String(localized: "Review grammar suggestions", bundle: .localizedModule))
    .accessibilityLabel(String(localized: "Review grammar suggestions", bundle: .localizedModule))
    .accessibilityValue("\(count)")
  }
}

struct GrammarReviewView: View {
  @Bindable var state: GrammarReviewState
  let profileChanged: (GrammarWritingProfile) -> Void
  let accept: (GrammarSuggestion) -> Void
  let dismiss: (GrammarSuggestion) -> Void
  let applyAll: () -> Void
  let undo: () -> Void
  let copy: () -> Void
  let retry: () -> Void
  let recheck: () -> Void
  let settings: () -> Void
  let enableClipboard: () -> Void
  let close: () -> Void
  var highlight: (UUID?) -> Void = { _ in }
  var resize: () -> Void = {}

  @State private var showOriginal = false
  @State private var visibleSuggestion: UUID?
  @State private var contentHeight: CGFloat = 0
  @State private var restoreKeyboardFocus = false
  @State private var hoveringSuggestions = false
  @FocusState private var focusedControl: GrammarReviewFocus?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(String(localized: "Grammar", bundle: .localizedModule))
          .font(.system(size: 14, weight: .semibold)).allowsHitTesting(false)
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary).frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Close", bundle: .localizedModule))
        .accessibilityLabel(String(localized: "Close", bundle: .localizedModule))
      }
      .background(GrammarPanelDragHandle().padding(.trailing, 28))

      HStack(spacing: 8) {
        Picker(
          String(localized: "Refinement", bundle: .localizedModule), selection: refinementBinding
        ) {
          ForEach(GrammarRefinement.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        if state.profile.refinement != .grammar {
          Picker(String(localized: "Tone", bundle: .localizedModule), selection: toneBinding) {
            ForEach(GrammarTone.allCases, id: \.self) { Text($0.displayName).tag($0) }
          }
          .labelsHidden()
        }
        Spacer(minLength: 0)
      }
      .pickerStyle(.menu)
      .controlSize(.small)
      .disabled(state.phase == .applying)

      status

      if case .rewrite(let text) = state.result {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Spacer()
            Toggle(String(localized: "Original", bundle: .localizedModule), isOn: $showOriginal)
              .toggleStyle(.button).controlSize(.mini)
          }
          ScrollView {
            Text(verbatim: showOriginal ? state.previewOriginalText : text)
              .font(.system(size: 13)).lineSpacing(3)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
              .padding(12)
              .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
              .background(heightReader)
          }
          .frame(height: max(48, contentHeight))
        }
      } else if !state.suggestions.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(state.suggestions) { suggestion in
              suggestionRow(suggestion).id(suggestion.id)
            }
          }
          .scrollTargetLayout()
          .background(heightReader)
        }
        .scrollPosition(id: $visibleSuggestion, anchor: .top)
        .onHover { hoveringSuggestions = $0 }
        .frame(height: max(48, contentHeight))
      } else if state.phase == .ready || state.phase == .completed {
        Text(state.completionText).font(.callout).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: max(48, contentHeight), alignment: .center)
      }

      if state.result != nil || state.hasUndo {
        Divider()
        footer
      }
    }
    .padding(16)
    .frame(width: 440)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
    .onPreferenceChange(GrammarContentHeightKey.self) { height in
      // Grow for real content, but keep the review stable as individual suggestions disappear.
      let next = max(contentHeight, min(320, ceil(height)))
      if next > contentHeight { contentHeight = next }
    }
    .onChange(of: contentHeight) { _, _ in resize() }
    .onChange(of: state.phase) { _, _ in resize() }
    .onChange(of: state.profile) { _, _ in
      showOriginal = false
      restoreKeyboardFocus = false
    }
    .onChange(of: state.focusRevision) { _, revision in
      guard restoreKeyboardFocus else { return }
      let target = state.focus
      focusedControl = nil
      Task { @MainActor in
        await Task.yield()
        if state.focusRevision == revision { focusedControl = target }
      }
    }
    .onAppear { if let id = state.highlighted { visibleSuggestion = id } }
    .onChange(of: state.highlighted) { _, id in
      // Hovering a row also highlights it; only scroll for one that is out of view.
      if let id, visibleSuggestion != id, !hoveringSuggestions { visibleSuggestion = id }
    }
    .onChange(of: state.suggestions.map(\.id)) { old, new in
      if let visibleSuggestion, !new.contains(visibleSuggestion),
        let index = old.firstIndex(of: visibleSuggestion)
      {
        self.visibleSuggestion = new.isEmpty ? nil : new[min(index, new.count - 1)]
      }
    }
  }

  private var heightReader: some View {
    GeometryReader { geometry in
      Color.clear.preference(key: GrammarContentHeightKey.self, value: geometry.size.height)
    }
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Button {
        userAction(copy)
      } label: {
        Label(String(localized: "Copy", bundle: .localizedModule), systemImage: "doc.on.doc")
          .font(.callout)
      }
      .buttonStyle(.borderless)
      .disabled(state.result == nil || state.phase == .applying)
      .focused($focusedControl, equals: .footer)
      if state.hasUndo {
        Button(String(localized: "Undo", bundle: .localizedModule)) { userAction(undo) }
          .buttonStyle(.borderless)
          .keyboardShortcut("z", modifiers: .command)
          .disabled(!state.canUndo)
      }
      Spacer()
      if state.phase == .applying { ProgressView().controlSize(.small) }
      if let suggestion = state.currentSuggestion {
        Button(String(localized: "Dismiss", bundle: .localizedModule)) {
          userAction { dismiss(suggestion) }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(state.phase != .ready)
        .focused($focusedControl, equals: state.sourceCanApply ? nil : .suggestion(suggestion.id))
        if state.sourceCanApply {
          Button(String(localized: "Accept", bundle: .localizedModule)) {
            userAction { accept(suggestion) }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(state.phase != .ready)
          .focused($focusedControl, equals: .suggestion(suggestion.id))
        }
      }
      if state.sourceCanApply, state.profile.refinement == .rewrite || state.suggestions.count > 1 {
        Button(
          state.profile.refinement == .rewrite
            ? String(localized: "Apply", bundle: .localizedModule)
            : String(localized: "Apply All", bundle: .localizedModule)
        ) { userAction(applyAll) }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!state.canApply)
      }
    }
    .frame(minHeight: 24)
  }

  @ViewBuilder
  private var status: some View {
    switch state.phase {
    case .checking:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(
          state.result == nil
            ? String(localized: "Checking…", bundle: .localizedModule)
            : String(localized: "Updating…", bundle: .localizedModule))
      }
      .font(.callout).foregroundStyle(.secondary)
      .padding(.vertical, state.result == nil ? 12 : 0)
    case .stale:
      HStack {
        Text(String(localized: "Text changed", bundle: .localizedModule)).foregroundStyle(
          .secondary)
        Spacer()
        Button(String(localized: "Recheck", bundle: .localizedModule), action: recheck)
          .controlSize(.small)
      }
    case .failed:
      if let failure = state.failure {
        VStack(alignment: .leading, spacing: 10) {
          Text(failure.message).font(.callout).foregroundStyle(.secondary)
          switch failure.recovery {
          case .retry: Button(String(localized: "Retry", bundle: .localizedModule), action: retry)
          case .settings:
            Button(
              String(localized: "Open Grammar settings", bundle: .localizedModule), action: settings
            )
          case .clipboard:
            Button(
              String(localized: "Enable clipboard fallback for this app", bundle: .localizedModule),
              action: enableClipboard)
          }
        }
        .controlSize(.small)
      }
    case .applying:
      Text(String(localized: "Applying…", bundle: .localizedModule)).font(.callout).foregroundStyle(
        .secondary)
    case .completed:
      if case .rewrite = state.result {
        Text(state.completionText).font(.callout).foregroundStyle(.secondary)
      }
    case .ready:
      if case .rewrite = state.result, !state.hasChanges {
        Text(String(localized: "No changes suggested", bundle: .localizedModule)).font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func suggestionRow(_ suggestion: GrammarSuggestion) -> some View {
    let isSelected = state.currentSuggestion?.id == suggestion.id
    let difference = GrammarTextDifference(
      original: suggestion.original, replacement: suggestion.replacement)
    return VStack(alignment: .leading, spacing: 8) {
      if suggestion.category != .correctness {
        Text(
          suggestion.category == .tone
            ? String(localized: "Tone", bundle: .localizedModule)
            : String(localized: "Clarity", bundle: .localizedModule)
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        differenceText(difference.original, removals: true).foregroundStyle(.secondary)
        if !suggestion.replacement.isEmpty {
          differenceText(difference.replacement, removals: false)
        }
      }
      .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      isSelected ? Color.accentColor.opacity(0.1) : .primary.opacity(0.035),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      if isSelected, state.suggestions.count > 1 {
        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.5))
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture {
      state.selected = suggestion.id
      highlight(suggestion.id)
    }
    .help(suggestion.explanation)
    .onHover { hovering in
      highlight(hovering ? suggestion.id : state.currentSuggestion?.id)
    }
  }

  private func differenceText(_ runs: [GrammarTextDifference.Run], removals: Bool) -> Text {
    runs.reduce(Text("")) { result, run in
      let span = Text(verbatim: run.text)
      guard run.changed else { return result + span }
      return result + (removals ? span.strikethrough() : span.bold().foregroundColor(.accentColor))
    }
  }

  private func userAction(_ action: () -> Void) {
    let event = NSApp.currentEvent?.type
    restoreKeyboardFocus = event == .keyDown || event == .keyUp
    action()
  }

  private var refinementBinding: Binding<GrammarRefinement> {
    Binding(
      get: { state.profile.refinement },
      set: {
        var profile = state.profile
        profile.refinement = $0
        profileChanged(profile)
      })
  }

  private var toneBinding: Binding<GrammarTone> {
    Binding(
      get: { state.profile.tone },
      set: {
        var profile = state.profile
        profile.tone = $0
        profileChanged(profile)
      })
  }
}

private struct GrammarContentHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct GrammarTextDifference {
  struct Run {
    let text: String
    let changed: Bool
  }

  let original: [Run]
  let replacement: [Run]

  init(original: String, replacement: String) {
    let before = Array(original)
    let after = Array(replacement)
    var removed: Set<Int> = []
    var inserted: Set<Int> = []
    for change in after.difference(from: before) {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    self.original = Self.runs(before, changed: removed)
    self.replacement = Self.runs(after, changed: inserted)
  }

  private static func runs(_ characters: [Character], changed: Set<Int>) -> [Run] {
    var runs: [Run] = []
    var text = ""
    var isChanged = false
    for (index, character) in characters.enumerated() {
      let nextChanged = changed.contains(index)
      if !text.isEmpty, nextChanged != isChanged {
        runs.append(Run(text: text, changed: isChanged))
        text = ""
      }
      text.append(character)
      isChanged = nextChanged
    }
    if !text.isEmpty { runs.append(Run(text: text, changed: isChanged)) }
    return runs
  }
}
