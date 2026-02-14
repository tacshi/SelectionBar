import MarkdownUI
import SwiftUI

struct ChatPanelView: View {
  @Bindable var session: ChatSession
  let selectedText: String
  let sourceURL: String?
  let canApply: Bool
  let showsSessionControls: Bool
  let savedSessions: () -> [ChatSessionRecord]
  let activeSessionID: () -> UUID?
  let restoredMessageCount: () -> Int
  let onCopy: (String) -> Void
  let onApply: (String) -> Void
  let onTogglePin: (Bool) -> Void
  let onNewSession: () -> Void
  let onSelectSession: (UUID) -> Void
  let onDismiss: () -> Void

  @State private var inputText = ""
  @State private var isContextExpanded = false
  @State private var isPinned = true
  @FocusState private var isInputFocused: Bool

  /// ID of the last restored message — used to place the session divider.
  private var lastRestoredMessageId: UUID? {
    let restoredCount = restoredMessageCount()
    guard restoredCount > 0, session.messages.count >= restoredCount else {
      return nil
    }
    return session.messages[restoredCount - 1].id
  }

  var body: some View {
    VStack(spacing: 0) {
      // Title bar
      titleBar

      Divider()

      // Context header
      contextHeader

      Divider()

      // Message list
      messageList

      Divider()

      // Input area
      inputArea
    }
    .frame(width: 420, height: 480)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
    )
    .task {
      try? await Task.sleep(for: .milliseconds(100))
      isInputFocused = true
    }
  }

  private var titleBar: some View {
    HStack {
      Button {
        isPinned.toggle()
        onTogglePin(isPinned)
      } label: {
        Image(systemName: isPinned ? "pin.fill" : "pin")
          .font(.system(size: 12))
          .foregroundStyle(isPinned ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      .focusable(false)
      .help(
        isPinned
          ? String(localized: "Unpin", bundle: .localizedModule)
          : String(localized: "Pin on Top", bundle: .localizedModule))

      sessionControls

      Spacer()

      Text("Chat", bundle: .localizedModule)
        .font(.callout)
        .fontWeight(.medium)

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .focusable(false)
      .help(String(localized: "Close", bundle: .localizedModule))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var sessionControls: some View {
    if showsSessionControls {
      let sessions = savedSessions()
      if sessions.isEmpty {
        Button {
          onNewSession()
        } label: {
          Image(systemName: "plus.message")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(String(localized: "New Session", bundle: .localizedModule))
      } else {
        Menu {
          Button {
            onNewSession()
          } label: {
            Label(
              String(localized: "New Session", bundle: .localizedModule),
              systemImage: "plus.message")
          }

          Divider()

          ForEach(sessions) { savedSession in
            Button {
              onSelectSession(savedSession.id)
            } label: {
              let sessionLabel =
                "\(savedSession.lastAccessedAt.formatted(date: .abbreviated, time: .shortened)) | \(savedSession.messages.count)"
              if savedSession.id == activeSessionID() {
                Label(sessionLabel, systemImage: "checkmark")
              } else {
                Text(sessionLabel)
              }
            }
            .disabled(savedSession.id == activeSessionID())
          }
        } label: {
          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusable(false)
        .disabled(session.isStreaming)
      }
    }
  }

  private var contextHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          isContextExpanded.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: isContextExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16)
          VStack(alignment: .leading, spacing: 2) {
            Text("Selected Text", bundle: .localizedModule)
              .font(.callout)
              .fontWeight(.medium)
              .foregroundStyle(.secondary)
            if let sourceURL {
              Text(sourceURL)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)

      if isContextExpanded {
        Text(selectedText)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(.primary.opacity(0.04), in: .rect(cornerRadius: 6))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(session.messages) { message in
            chatMessageView(message)
              .id(message.id)

            if message.id == lastRestoredMessageId {
              sessionDivider
            }
          }

          if session.pendingSourceRead {
            HStack(spacing: 8) {
              Image(systemName: session.sourceKind == .webPage ? "globe" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
              Group {
                switch session.sourceKind {
                case .webPage:
                  Text("AI wants to read the web page", bundle: .localizedModule)
                case .file, nil:
                  Text("AI wants to read the source file", bundle: .localizedModule)
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
              Spacer()
              Button(String(localized: "Allow", bundle: .localizedModule)) {
                session.approveSourceRead()
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              Button(String(localized: "Skip", bundle: .localizedModule)) {
                session.denySourceRead()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
          }

          if session.isReadingSource {
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.small)
              Text("Reading source...", bundle: .localizedModule)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
          }

          if let error = session.error {
            HStack(alignment: .top, spacing: 6) {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
              Spacer()
              Button {
                session.retryLastMessage()
              } label: {
                Image(systemName: "arrow.clockwise")
                  .font(.system(size: 12))
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help(String(localized: "Retry", bundle: .localizedModule))
            }
            .padding(.horizontal, 12)
          }
        }
        .padding(12)
      }
      .defaultScrollAnchor(.bottom)
      .onChange(of: session.messages.count) { _, _ in
        if let lastId = session.messages.last?.id {
          withAnimation {
            proxy.scrollTo(lastId, anchor: .bottom)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func chatMessageView(_ message: ChatMessage) -> some View {
    switch message.role {
    case .user:
      HStack {
        Spacer(minLength: 60)
        Text(message.content)
          .font(.callout)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 10))
      }
    case .assistant:
      let isActivelyStreaming =
        session.isStreaming && message.id == session.messages.last?.id
      VStack(alignment: .leading, spacing: 4) {
        if isActivelyStreaming {
          // Use plain Text during streaming to avoid expensive Markdown re-parsing per token
          Text(message.content)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Markdown(message.content)
            .markdownTheme(.chatCompact)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !message.content.isEmpty && !isActivelyStreaming {
          HStack(spacing: 8) {
            Button {
              onCopy(message.content)
            } label: {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "Copy Response", bundle: .localizedModule))

            if canApply {
              Button {
                onApply(message.content)
              } label: {
                Image(systemName: "text.badge.checkmark")
                  .font(.system(size: 11))
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help(String(localized: "Apply Response", bundle: .localizedModule))
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var sessionDivider: some View {
    HStack(spacing: 8) {
      Rectangle()
        .fill(.tertiary)
        .frame(height: 1)
      Text("Session resumed", bundle: .localizedModule)
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .layoutPriority(1)
      Rectangle()
        .fill(.tertiary)
        .frame(height: 1)
    }
    .padding(.vertical, 4)
  }

  private var inputArea: some View {
    HStack(spacing: 8) {
      TextField(
        String(localized: "Type a message...", bundle: .localizedModule),
        text: $inputText
      )
      .textFieldStyle(.plain)
      .font(.callout)
      .focused($isInputFocused)
      .onSubmit {
        sendMessage()
      }
      .disabled(session.isStreaming)

      if session.isStreaming {
        Button {
          session.cancelStreaming()
        } label: {
          Image(systemName: "stop.fill")
            .font(.system(size: 12))
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .help(String(localized: "Stop", bundle: .localizedModule))
      } else {
        Button {
          sendMessage()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 18))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
          inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor)
        )
        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(String(localized: "Send", bundle: .localizedModule))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func sendMessage() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    inputText = ""
    session.sendMessage(text)
  }
}

extension MarkdownUI.Theme {
  @MainActor static var chatCompact: Theme {
    Theme.gitHub
      .text {
        FontSize(.em(0.85))
      }
      .heading1 { configuration in
        configuration.label
          .markdownMargin(top: 12, bottom: 4)
          .markdownTextStyle {
            FontSize(.em(1.1))
            FontWeight(.semibold)
          }
      }
      .heading2 { configuration in
        configuration.label
          .markdownMargin(top: 10, bottom: 4)
          .markdownTextStyle {
            FontSize(.em(1.0))
            FontWeight(.semibold)
          }
      }
      .heading3 { configuration in
        configuration.label
          .markdownMargin(top: 8, bottom: 4)
          .markdownTextStyle {
            FontSize(.em(0.9))
            FontWeight(.semibold)
          }
      }
  }
}
