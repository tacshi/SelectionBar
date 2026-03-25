import AppKit
import SwiftUI

/// Horizontal floating button bar for built-in text actions.
struct SelectionBarView: View {
  @Environment(\.colorScheme) private var colorScheme

  let actions: [CustomActionConfig]
  let processingActionId: UUID?
  let errorActionId: UUID?
  let showCut: Bool
  let showSearch: Bool
  let showOpenURL: Bool
  let showRunCommand: Bool
  let isRunningCommand: Bool
  let isRunCommandError: Bool
  let showLookup: Bool
  let showTranslate: Bool
  let isTranslating: Bool
  let isTranslateError: Bool
  let showSpeak: Bool
  let isSpeaking: Bool
  let showChat: Bool
  let isBusy: Bool
  let onSearchSelected: () -> Void
  let onOpenURLSelected: () -> Void
  let onRunCommandSelected: () -> Void
  let onCopySelected: () -> Void
  let onCutSelected: () -> Void
  let onLookupSelected: () -> Void
  let onTranslateSelected: () -> Void
  let onSpeakSelected: () -> Void
  let onChatSelected: () -> Void
  let onActionSelected: (CustomActionConfig) -> Void

  private let barCornerRadius: CGFloat = 16
  private let controlCornerRadius: CGFloat = 10

  var body: some View {
    HStack(spacing: 6) {
      actionButton(
        title: String(localized: "Copy", bundle: .localizedModule),
        systemImage: "doc.on.doc", action: onCopySelected
      )
      if showCut {
        actionButton(
          title: String(localized: "Cut", bundle: .localizedModule),
          systemImage: "scissors", action: onCutSelected
        )
      }

      if showSearch {
        actionButton(
          title: String(localized: "Web Search", bundle: .localizedModule),
          systemImage: "magnifyingglass", action: onSearchSelected
        )
      }

      if showOpenURL {
        actionButton(
          title: String(localized: "Open URL", bundle: .localizedModule),
          systemImage: "link", action: onOpenURLSelected
        )
      }

      if showRunCommand {
        let title = String(localized: "Run Command", bundle: .localizedModule)
        Button(action: onRunCommandSelected) {
          if isRunningCommand {
            ProgressView()
              .controlSize(.small)
              .frame(width: 18, height: 18)
          } else {
            Image(systemName: "terminal")
              .font(.system(size: 14, weight: .medium))
              .frame(width: 18, height: 18)
          }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
          controlBackground(isError: isRunCommandError)
        }
        .foregroundStyle(isRunCommandError ? Color.red : Color.primary)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(isBusy)
      }

      if showLookup {
        actionButton(
          title: String(localized: "Look Up", bundle: .localizedModule),
          systemImage: "book.closed", action: onLookupSelected
        )
      }

      if showTranslate {
        let translateTitle = String(localized: "Translate", bundle: .localizedModule)
        Button(action: onTranslateSelected) {
          Image(systemName: "translate")
            .font(.system(size: 14, weight: .medium))
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
          controlBackground(isError: isTranslateError)
        }
        .foregroundStyle(isTranslateError ? Color.red : Color.primary)
        .overlay {
          if isTranslating {
            ProgressView()
              .controlSize(.small)
          }
        }
        .help(translateTitle)
        .accessibilityLabel(Text(translateTitle))
        .disabled(isBusy)
      }

      if showSpeak {
        let speakTitle =
          isSpeaking
          ? String(localized: "Stop", bundle: .localizedModule)
          : String(localized: "Speak", bundle: .localizedModule)
        let speakIcon = isSpeaking ? "stop.fill" : "speaker.wave.2"
        Button(action: onSpeakSelected) {
          Image(systemName: speakIcon)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
          controlBackground(isAccent: isSpeaking)
        }
        .foregroundStyle(isSpeaking ? Color.accentColor : Color.primary)
        .help(speakTitle)
        .accessibilityLabel(Text(speakTitle))
        .disabled(isBusy)
      }

      if showChat {
        actionButton(
          title: String(localized: "Chat", bundle: .localizedModule),
          systemImage: "ellipsis.message",
          action: onChatSelected
        )
      }

      if !actions.isEmpty {
        Rectangle()
          .fill(Color(nsColor: .separatorColor))
          .frame(width: 1, height: 18)
          .padding(.horizontal, 4)
      }

      ForEach(actions) { action in
        Button {
          onActionSelected(action)
        } label: {
          if processingActionId == action.id {
            ProgressView()
              .controlSize(.small)
              .frame(width: 14, height: 14)
          } else {
            actionIcon(for: action)
          }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
          controlBackground(isError: errorActionId == action.id)
        }
        .foregroundStyle(buttonForeground(for: action))
        .help(actionHelpText(for: action))
        .disabled(isBusy)
        .accessibilityLabel(Text(action.localizedName))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background {
      barBackground
        .allowsHitTesting(false)
    }
    .overlay {
      barShape
        .strokeBorder(
          LinearGradient(
            colors: [
              .white.opacity(colorScheme == .dark ? 0.22 : 0.62),
              .white.opacity(colorScheme == .dark ? 0.05 : 0.14),
            ],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 1
        )
        .allowsHitTesting(false)
    }
    .overlay {
      barShape
        .fill(
          LinearGradient(
            colors: [
              .white.opacity(colorScheme == .dark ? 0.12 : 0.26),
              .clear,
            ],
            startPoint: .top,
            endPoint: .center
          )
        )
        .allowsHitTesting(false)
    }
  }

  private func actionButton(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .medium))
        .frame(width: 18, height: 18)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background {
      controlBackground()
    }
    .foregroundStyle(.primary)
    .help(title)
    .accessibilityLabel(Text(title))
    .disabled(isBusy)
  }

  private var barShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
  }

  @ViewBuilder
  private var barBackground: some View {
    if #available(macOS 26.0, *) {
      Color.clear
        .glassEffect(.regular, in: barShape)
    } else {
      FloatingBarMaterialBackground(cornerRadius: barCornerRadius)
        .overlay {
          barShape
            .fill(
              LinearGradient(
                colors: [
                  .white.opacity(colorScheme == .dark ? 0.05 : 0.18),
                  .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
        }
    }
  }

  @ViewBuilder
  private func controlBackground(
    isAccent: Bool = false,
    isError: Bool = false
  ) -> some View {
    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
      .fill(controlFillColor(isAccent: isAccent, isError: isError))
      .overlay {
        RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
          .strokeBorder(controlStrokeColor(isAccent: isAccent, isError: isError), lineWidth: 0.75)
      }
  }

  private func buttonForeground(for action: CustomActionConfig) -> Color {
    if errorActionId == action.id {
      return .red
    }
    return .primary
  }

  private func actionHelpText(for action: CustomActionConfig) -> String {
    guard action.kind == .keyBinding,
      let shortcut = SelectionBarKeyboardShortcutParser.parse(action.keyBinding)
    else {
      return action.localizedName
    }
    return "\(action.localizedName) (\(shortcut.displayString))"
  }

  @ViewBuilder
  private func actionIcon(for action: CustomActionConfig) -> some View {
    Image(systemName: action.effectiveIcon.resolvedValue)
      .font(.system(size: 14, weight: .medium))
      .frame(width: 18, height: 18)
  }

  private func controlFillColor(isAccent: Bool, isError: Bool) -> Color {
    if isError {
      return .red.opacity(colorScheme == .dark ? 0.24 : 0.18)
    }
    if isAccent {
      return .accentColor.opacity(colorScheme == .dark ? 0.22 : 0.16)
    }
    return colorScheme == .dark
      ? .white.opacity(0.08)
      : .white.opacity(0.28)
  }

  private func controlStrokeColor(isAccent: Bool, isError: Bool) -> Color {
    if isError {
      return .red.opacity(colorScheme == .dark ? 0.4 : 0.26)
    }
    if isAccent {
      return .accentColor.opacity(colorScheme == .dark ? 0.34 : 0.24)
    }
    return colorScheme == .dark
      ? .white.opacity(0.12)
      : .white.opacity(0.52)
  }
}

private struct FloatingBarMaterialBackground: NSViewRepresentable {
  let cornerRadius: CGFloat

  func makeNSView(context: Context) -> PassthroughVisualEffectView {
    let view = PassthroughVisualEffectView()
    configure(view)
    return view
  }

  func updateNSView(_ nsView: PassthroughVisualEffectView, context: Context) {
    configure(nsView)
  }

  private func configure(_ view: NSVisualEffectView) {
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.masksToBounds = true
  }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hitView = super.hitTest(point)
    return hitView === self ? nil : hitView
  }
}
