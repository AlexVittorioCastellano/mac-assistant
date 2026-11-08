import AssistenteCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AssistantViewModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ForEach(model.alerts.active) { alert in
                AlertBanner(alert: alert) { model.ask(alert.question) }
            }
            inputRow
            quickActions
            if model.isChatting {
                Divider()
                ChatView(model: model)
            } else if model.isWorking || !model.choices.isEmpty || !model.findings.isEmpty || !model.answer.isEmpty
                        || model.notice != nil || !model.cleanupItems.isEmpty {
                Divider()

                if isLongResult {
                    ScrollView {
                        results.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: min(scrollHeight, estimatedResultsHeight))
                } else {
                    results.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)

        .id(model.languageCode ?? "auto")

        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return false }
            model.explainImage(data)
            return true
        }
        .onAppear {
            fieldFocused = true
            model.prewarmTextRecognition()
        }
    }

    @ViewBuilder private func resultActions(advice: [String]) -> some View {
        HStack(spacing: 8) {
            let reading = model.speech.speakingID == "result"
            Button {
                model.speech.toggle(ReadAloud.text(findings: model.findings, answer: model.answer), id: "result")
            } label: {
                Label(reading ? L.t("ui.stopReading") : L.t("ui.readAloud"),
                      systemImage: reading ? "stop.circle" : "speaker.wave.2")
            }
            if let report = model.helperReport {
                Button { model.copyHelperReport() } label: {
                    Label(L.t("ui.report.copyShort"), systemImage: "doc.on.doc")
                }
                .help(L.t("ui.report.copy"))
                ShareLink(item: report) { Label(L.t("ui.report.share"), systemImage: "square.and.arrow.up") }
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    private var isLongResult: Bool {
        let rows = model.findings.count + Finding.advice(from: model.findings).count + model.cleanupItems.count * 2
        return rows + (model.chart != nil ? 5 : 0) > 11
    }

    private var estimatedResultsHeight: CGFloat {
        let advice = Finding.advice(from: model.findings)
        var h: CGFloat = 50
        h += CGFloat(model.findings.count) * 30
        h += advice.reduce(0) { $0 + 22 * CGFloat(1 + $1.count / 55) } + (advice.isEmpty ? 0 : 30)
        h += model.answer.isEmpty ? 0 : 22 * CGFloat(1 + model.answer.count / 55)
        h += model.chart != nil ? 170 : 0
        h += CGFloat(model.cleanupItems.count) * 48 + (model.cleanupItems.isEmpty ? 0 : 140)
        return h
    }

    private var scrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(300, min(620, screen - 330))
    }

    private var header: some View {
        Label("Mac Assistant", systemImage: "questionmark.bubble.fill")
            .font(.headline)
    }

    private var inputRow: some View {
        HStack {
            TextField(model.isListening ? L.t("ui.field.listening")
                      : model.isChatting ? L.t("ui.field.chat") : L.t("ui.field.ask"),
                      text: $model.question)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { model.ask() }

            Button {
                model.toggleVoice()
            } label: {
                Image(systemName: model.isListening ? "mic.circle.fill" : "mic.circle")
                    .font(.title2)
                    .foregroundStyle(model.isListening ? Color.red : Color.secondary)
                    .symbolEffect(.pulse, isActive: model.isListening)
            }
            .buttonStyle(.plain)
            .help(model.isListening ? L.t("ui.mic.stop.help") : L.t("ui.mic.start.help"))
            .accessibilityLabel(model.isListening ? L.t("ui.mic.stop.a11y") : L.t("ui.mic.start.a11y"))
            Button {
                model.ask()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(L.t("ui.send"))
        }
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            Button {
                model.ask(Assistant.healthQuestion)
            } label: {
                Label(L.t("ui.button.health"), systemImage: "stethoscope")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help(L.t("ui.button.health.help"))

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    quickButton(L.t("ui.button.slow"), question: Assistant.slowMacQuestion, icon: "tortoise")
                    quickButton(L.t("ui.button.processes"), question: Assistant.processQuestion, icon: "questionmark.app")
                }
                GridRow {
                    quickButton(L.t("ui.button.disk"), question: Assistant.diskQuestion, icon: "internaldrive")
                    Button {
                        model.explainClipboard()
                    } label: {
                        Label(L.t("ui.button.message"), systemImage: "text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help(L.t("ui.button.message.help"))
                }
                GridRow {
                    quickButton(L.t("ui.button.security"), question: Assistant.securityQuestion, icon: "exclamationmark.shield")
                    quickButton(L.t("ui.button.cleanup"), question: Assistant.cleanupQuestion, icon: "sparkles")
                }
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
                .frame(maxWidth: .infinity)
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
            if !model.isWorking && (!model.findings.isEmpty || !model.answer.isEmpty) {
                resultActions(advice: advice)
            }
            if !advice.isEmpty && !model.isWorking {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("ui.advice.header")).font(.subheadline.bold())
                    ForEach(advice, id: \.self) { item in
                        Label(item, systemImage: "arrow.right.circle")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !model.cleanupItems.isEmpty {
                CleanupView(model: model)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.lastTrash != nil {
                    Button(L.t("ui.cleanup.undo")) { model.undoCleanup() }
                        .controlSize(.small)
                }
            }
            if !model.choices.isEmpty {
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
                    Text(model.findings.isEmpty ? model.workingLabel : L.t("ui.working.explain"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.isOnDevice {
                Label(L.t("ui.footer.private"), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Toggle(L.t("ui.settings.alerts"), isOn: Binding(get: { model.alerts.enabled },
                                                          set: { model.alerts.enabled = $0 }))
                Toggle(L.t("ui.settings.launch"), isOn: $model.launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                Divider()
                Text(model.hotKey != nil ? L.t("ui.settings.hotkey", GlobalHotKey.label)
                                         : L.t("ui.settings.hotkey.taken", GlobalHotKey.label))

                Picker(L.t("ui.settings.language"), selection: $model.languageCode) {
                    Text(L.t("ui.settings.language.auto")).tag(String?.none)
                    ForEach(L.available, id: \.code) { pack in
                        Text(pack.name).tag(String?.some(pack.code))
                    }
                }
                Button(L.t("ui.settings.welcome")) { model.showWelcome() }
                Divider()
                Button(L.t("ui.settings.quit")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L.t("ui.settings"))
        }
    }
}

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

private struct AlertBanner: View {
    let alert: MacAlert
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title).font(.callout.weight(.semibold))
                Text(alert.body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(L.t("ui.alert.see"), action: action)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
