import AssistenteCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AssistantViewModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            inputRow
            quickActions
            if model.isWorking || !model.choices.isEmpty || !model.findings.isEmpty || !model.answer.isEmpty || model.notice != nil {
                Divider()
                // Niente ScrollView: dentro un MenuBarExtra non ha un'altezza
                // naturale e si riduce a zero (i risultati sparivano).
                // Le risposte sono brevi, quindi il riquadro si adatta al testo.
                results.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        Label("Assistente Mac", systemImage: "questionmark.bubble.fill")
            .font(.headline)
    }

    private var inputRow: some View {
        HStack {
            TextField("Fai una domanda sul tuo Mac…", text: $model.question)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { model.ask() }
            Button {
                model.ask()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Invia")
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickButton(Assistant.slowMacQuestion, icon: "tortoise")
            quickButton(Assistant.processQuestion, icon: "questionmark.app")
        }
        .controlSize(.small)
        .disabled(model.isWorking)
    }

    private func quickButton(_ question: String, icon: String) -> some View {
        Button {
            model.ask(question)
        } label: {
            Label(question, systemImage: icon)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.findings) { finding in
                FindingRow(finding: finding)
            }
            if !model.answer.isEmpty {
                Text(markdown(model.answer))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let advice = Finding.advice(from: model.findings)
            if !advice.isEmpty && !model.isWorking {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cosa puoi fare").font(.subheadline.bold())
                    ForEach(advice, id: \.self) { item in
                        Label(item, systemImage: "arrow.right.circle")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.choices.isEmpty {
                // Processi tra cui scegliere: un clic fa la domanda.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.choices, id: \.self) { choice in
                        Button(choice.label) { model.ask(choice.question) }
                            .buttonStyle(.link)
                    }
                }
                .padding(.leading, 24)
            }
            if model.isWorking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.findings.isEmpty ? "Controllo il Mac…" : "Preparo la spiegazione…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.isOnDevice {
                Label("Tutto resta sul tuo Mac", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Esci") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    /// Il modello può rispondere con un po' di Markdown (grassetti, elenchi).
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        Label {
            Text(finding.title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }

    private var icon: String {
        switch finding.severity {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    private var color: Color {
        switch finding.severity {
        case .ok: .green
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}
