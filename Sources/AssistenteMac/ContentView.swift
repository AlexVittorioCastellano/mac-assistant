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
            if model.isChatting {
                Divider()
                ChatView(model: model)
            } else if model.isWorking || !model.choices.isEmpty || !model.findings.isEmpty || !model.answer.isEmpty || model.notice != nil {
                Divider()
                // Dentro un MenuBarExtra uno ScrollView senza altezza si riduce a
                // zero. Le risposte brevi si mostrano così come sono; quelle
                // lunghe (es. il controllo generale) scorrono in un'area di
                // altezza FISSA, calcolata perché il riquadro stia sullo schermo
                // anche di un MacBook da 13".
                if isLongResult {
                    ScrollView {
                        results.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: scrollHeight)
                } else {
                    results.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
        .onAppear { fieldFocused = true }
    }

    /// Stima prudente: molte righe (o il grafico) = risultato lungo.
    private var isLongResult: Bool {
        let rows = model.findings.count + Finding.advice(from: model.findings).count
        return rows + (model.chart != nil ? 5 : 0) > 11
    }

    /// Altezza dell'area a scorrimento: quanto resta sullo schermo tolta la
    /// parte fissa del riquadro (campo, pulsanti, piè di pagina ≈ 300 punti).
    private var scrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(300, min(620, screen - 330))
    }

    private var header: some View {
        Label("Assistente Mac", systemImage: "questionmark.bubble.fill")
            .font(.headline)
    }

    private var inputRow: some View {
        HStack {
            TextField(model.isChatting ? "Scrivi un altro messaggio…" : "Fai una domanda sul tuo Mac…",
                      text: $model.question)
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
        // Etichette brevi per farci stare tre pulsanti; la domanda completa
        // compare passandoci sopra con il mouse.
        VStack(spacing: 8) {
            // Il pulsante principale: un controllo generale in un clic.
            Button {
                model.ask(Assistant.healthQuestion)
            } label: {
                Label("Controlla il mio Mac", systemImage: "stethoscope")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Velocità, spazio, backup, sicurezza, aggiornamenti e batteria in un colpo solo")

            HStack(spacing: 8) {
            quickButton("Mac lento", question: Assistant.slowMacQuestion, icon: "tortoise")
            quickButton("Processi", question: Assistant.processQuestion, icon: "questionmark.app")
            quickButton("Spazio disco", question: Assistant.diskQuestion, icon: "internaldrive")
            }
            .controlSize(.regular)
        }
        .disabled(model.isWorking)
    }

    private func quickButton(_ label: String, question: String, icon: String) -> some View {
        Button {
            model.ask(question)
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .help(question)
    }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let chart = model.chart {
                DiskChartView(chart: chart, hover: $model.chartHover)
                    .padding(.bottom, 4)
            }
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
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.choices, id: \.self) { choice in
                        Button { model.ask(choice.question) } label: {
                            HStack(spacing: 8) {
                                ItemIcon(path: choice.iconPath, symbol: choice.symbol, tint: .secondary)
                                Text(choice.label).foregroundStyle(.link)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

}

/// Il modello può rispondere con un po' di Markdown (grassetti, elenchi).
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        if finding.id == "overall" {
            headline
        } else {
            row
        }
    }

    /// Il semaforo del controllo generale: grande, in un riquadro colorato.
    private var headline: some View {
        HStack(spacing: 10) {
            Image(systemName: finding.symbol ?? icon)
                .font(.title)
                .foregroundStyle(color)
            Text(finding.title)
                .font(.title3.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let swatch = finding.swatch {
                // Pallino dello stesso colore del blocco nella barra (fa da legenda).
                SwatchDot(swatch: swatch)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            Group {
                if finding.iconPath != nil || finding.symbol != nil {
                    ItemIcon(path: finding.iconPath, symbol: finding.symbol ?? icon, tint: color)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                } else {
                    Image(systemName: icon).foregroundStyle(color)
                        .frame(width: 20)
                }
            }
            Text(finding.title).fixedSize(horizontal: false, vertical: true)
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

/// Icona di un elemento: quella del Finder per un file/cartella/app
/// (come la mostra il Finder), altrimenti un simbolo SF.
struct ItemIcon: View {
    let path: String?
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Group {
            if let path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 20, height: 20)
    }
}
