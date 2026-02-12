import SwiftUI

/// Horizontal floating button bar for built-in text actions.
struct SelectionBarView: View {
    let actions: [CustomActionConfig]
    let processingActionId: UUID?
    let errorActionId: UUID?
    let showCut: Bool
    let showSearch: Bool
    let showOpenURL: Bool
    let showLookup: Bool
    let showTranslate: Bool
    let isTranslating: Bool
    let isTranslateError: Bool
    let showSpeak: Bool
    let isSpeaking: Bool
    let isBusy: Bool
    let onSearchSelected: () -> Void
    let onOpenURLSelected: () -> Void
    let onCopySelected: () -> Void
    let onCutSelected: () -> Void
    let onLookupSelected: () -> Void
    let onTranslateSelected: () -> Void
    let onSpeakSelected: () -> Void
    let onActionSelected: (CustomActionConfig) -> Void

    var body: some View {
        HStack {
            actionButton(
                title: String(localized: "Copy", bundle: .module),
                systemImage: "doc.on.doc", action: onCopySelected
            )
            if showCut {
                actionButton(
                    title: String(localized: "Cut", bundle: .module),
                    systemImage: "scissors", action: onCutSelected
                )
            }

            if showSearch {
                actionButton(
                    title: String(localized: "Web Search", bundle: .module),
                    systemImage: "magnifyingglass", action: onSearchSelected
                )
            }

            if showOpenURL {
                actionButton(
                    title: String(localized: "Open URL", bundle: .module),
                    systemImage: "link", action: onOpenURLSelected
                )
            }

            if showLookup {
                actionButton(
                    title: String(localized: "Look Up", bundle: .module),
                    systemImage: "book.closed", action: onLookupSelected
                )
            }

            if showTranslate {
                let translateTitle = String(localized: "Translate", bundle: .module)
                Button(action: onTranslateSelected) {
                    Image(systemName: "translate")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    isTranslateError ? Color.red.opacity(0.2) : Color.primary.opacity(0.08),
                    in: .rect(cornerRadius: 6)
                )
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
                    ? String(localized: "Stop", bundle: .module)
                    : String(localized: "Speak", bundle: .module)
                let speakIcon = isSpeaking ? "stop.fill" : "speaker.wave.2"
                Button(action: onSpeakSelected) {
                    Image(systemName: speakIcon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    isSpeaking ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08),
                    in: .rect(cornerRadius: 6)
                )
                .foregroundStyle(isSpeaking ? Color.accentColor : Color.primary)
                .help(speakTitle)
                .accessibilityLabel(Text(speakTitle))
                .disabled(isBusy)
            }

            if !actions.isEmpty {
                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(buttonBackground(for: action), in: .rect(cornerRadius: 6))
                .foregroundStyle(buttonForeground(for: action))
                .help(action.localizedName)
                .disabled(isBusy)
                .accessibilityLabel(Text(action.localizedName))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: .rect(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 6))
        .foregroundStyle(.primary)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(isBusy)
    }

    private func buttonBackground(for action: CustomActionConfig) -> Color {
        if errorActionId == action.id {
            return .red.opacity(0.2)
        }
        return .primary.opacity(0.08)
    }

    private func buttonForeground(for action: CustomActionConfig) -> Color {
        if errorActionId == action.id {
            return .red
        }
        return .primary
    }

    @ViewBuilder
    private func actionIcon(for action: CustomActionConfig) -> some View {
        Image(systemName: action.effectiveIcon.resolvedValue)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 18, height: 18)
    }
}
