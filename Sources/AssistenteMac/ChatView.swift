import AssistenteCore
import SwiftUI

struct ChatView: View {
    @Bindable var model: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.messages) { message in
                            Bubble(message: message, speech: model.speech).id(message.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 340)

                .onChange(of: model.messages.last?.text) {
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack {
                Text(L.t("ui.chat.disclaimer"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    model.newConversation()
                } label: {
                    Label(L.t("ui.chat.new"), systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage
    let speech: SpeechService

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }

    @ViewBuilder private var content: some View {
        if message.role == .assistant && message.text.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L.t("ui.chat.thinking")).foregroundStyle(.secondary)
            }
        } else if message.isError {
            Label(message.text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown(message.text))
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !message.verifiedGuides.isEmpty {
                    VerifiedGuideBox(guides: message.verifiedGuides)
                } else if message.basedOnGuide {
                    Label(L.t("ui.chat.guided"), systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .help(L.t("ui.chat.guided.help"))
                }
                if message.role == .assistant && !message.isError {
                    let reading = speech.speakingID == message.id.uuidString
                    Button {
                        speech.toggle(ReadAloud.speakable(message.text), id: message.id.uuidString)
                    } label: {
                        Label(reading ? L.t("ui.stopReading") : L.t("ui.readAloud"),
                              systemImage: reading ? "stop.circle" : "speaker.wave.2")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
                if !message.verifiedGuides.isEmpty || message.basedOnGuide {
                    EmptyView()
                } else if message.role == .assistant {
                    Label(L.t("ui.chat.unguided"), systemImage: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help(L.t("ui.chat.unguided.help"))
                }
            }
        }
    }

    private var background: Color {
        message.role == .user ? Color.accentColor : Color.primary.opacity(0.07)
    }
}

private struct VerifiedGuideBox: View {
    let guides: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L.t("ui.chat.verifiedGuide"), systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            ForEach(guides, id: \.self) { guide in
                Text(guide)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
