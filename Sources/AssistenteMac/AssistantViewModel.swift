import AppKit
import AssistenteCore
import AVFoundation
import Observation
import os
import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var isError = false

    var verifiedGuides: [String] = []

    var basedOnGuide = false
}

@MainActor
@Observable
final class AssistantViewModel {
    var question = ""
    var findings: [Finding] = []
    var choices: [Choice] = []
    var chart: SegmentedChart?

    var chartHover: Double?
    var answer = ""
    var notice: String?
    var isWorking = false

    var workingLabel = L.t("ui.working.check")
    private var lastPrewarm = Date.distantPast

    var cleanupItems: [CleanupItem] = []
    var cleanupSelected: Set<String> = []
    var confirmCleanup = false
    private(set) var lastTrash: Cleanup.TrashResult?

    var selectedCleanupItems: [CleanupItem] { cleanupItems.filter { cleanupSelected.contains($0.id) } }
    var selectedCleanupBytes: UInt64 { selectedCleanupItems.reduce(0) { $0 + $1.bytes } }

    var isListening = false
    private var dictation: LiveDictation?
    private var listenTimeout: Task<Void, Never>?

    var messages: [ChatMessage] = []
    private var chat: (any AIChatSession)?

    private var chatGuides: [String] = []
    var isChatting: Bool { !messages.isEmpty }

    let alerts = AlertService()

    let speech = SpeechService()

    var isHealthResult: Bool {
        findings.first?.id == "overall" && findings.contains { $0.id == "speed" }
    }

    var helperReport: String? {
        isHealthResult ? HelperReport.text(findings: findings) : nil
    }

    func copyHelperReport() {
        guard let text = helperReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = L.t("ui.report.copied")
    }

    private(set) var hotKey: GlobalHotKey?
    private let welcome = WelcomeWindow()

    var launchAtLogin: Bool = LaunchAtLogin.isEnabled {
        didSet { LaunchAtLogin.isEnabled = launchAtLogin; launchAtLogin = LaunchAtLogin.isEnabled }
    }

    var languageCode: String? = UserDefaults.standard.string(forKey: "lingua") {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: "lingua")
            L.override = languageCode
            newConversation()
        }
    }

    func appDidLaunch() {
        L.override = languageCode
        alerts.start()
        prewarmTextRecognition()
        hotKey = GlobalHotKey { [weak self] in
            MainActor.assumeIsolated { self?.toggleQuickPanel() }
        }
        if !WelcomeWindow.wasShown { showWelcome() }
    }

    private let quickPanel = QuickPanel()

    func toggleQuickPanel() {
        quickPanel.toggle(model: self)
    }

    func showWelcome() {
        welcome.show(alerts: alerts, hotKeyWorks: hotKey != nil)
    }

    private let assistant = Assistant()
    private let log = Logger(subsystem: "AssistenteMac", category: "ui")
    private var task: Task<Void, Never>?

    var isOnDevice: Bool { assistant.provider.isOnDevice }

    func ask(_ text: String? = nil) {
        let q = (text ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("ask: \(q, privacy: .public)")
        guard !q.isEmpty else { return }
        question = q
        let guides = isChatting ? chatGuides : []
        run { [assistant] in try await assistant.prepare(question: q, conversationGuides: guides) }
    }

    func explainClipboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            explainImage(data)
        } else if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
                  let data = try? Data(contentsOf: url) {
            explainImage(data)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            question = Assistant.messageQuestion
            run(label: L.t("ui.working.message")) { [assistant] in assistant.explainMessage(text) }
        } else {
            question = Assistant.messageQuestion
            endChat()
            clearResults()
            notice = L.t("ui.message.clipboardEmpty")
        }
    }

    func explainImage(_ data: Data) {
        question = Assistant.messageQuestion
        run(label: L.t("ui.working.message")) { [assistant] in try await assistant.explainMessage(imageData: data) }

        Task {
            try? await Task.sleep(for: .seconds(4))
            if isWorking && findings.isEmpty && notice == nil {
                workingLabel = L.t("ui.working.message.slow")
            }
        }
    }

    func toggleVoice() {
        if isListening { finishListening() } else { startListening() }
    }

    private func startListening() {
        guard Bundle.main.bundleIdentifier != nil else {
            notice = L.t("ui.voice.needsApp")
            return
        }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                notice = L.t("ui.voice.micDenied")
                return
            }
            guard await VoiceTranscriber.isAvailable() else {
                notice = L.t("ui.voice.noLanguage")
                return
            }
            task?.cancel()
            clearResults()
            question = ""
            let dictation = LiveDictation()
            self.dictation = dictation
            isListening = true
            do {
                try await dictation.start { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.isListening else { return }
                        self.question = text
                    }
                }
            } catch {
                isListening = false
                self.dictation = nil
                notice = error.localizedDescription
                return
            }

            listenTimeout = Task {
                try? await Task.sleep(for: .seconds(30))
                if isListening { finishListening() }
            }
        }
    }

    private func finishListening() {
        guard let dictation else { return }
        isListening = false
        listenTimeout?.cancel()
        self.dictation = nil
        Task {
            let text = await dictation.stop()
            question = text
            if text.isEmpty {
                notice = L.t("ui.voice.nothingHeard")
            } else {
                ask(text)
            }
        }
    }

    func prewarmTextRecognition() {
        guard Date().timeIntervalSince(lastPrewarm) > 300 else { return }
        lastPrewarm = Date()
        TextRecognizer.prewarm()
    }

    private func run(label: String = L.t("ui.working.check"),
                     _ produce: @escaping @Sendable () async throws -> AssistantReply) {
        task?.cancel()
        clearResults()
        workingLabel = label
        isWorking = true
        let q = question

        task = Task {
            defer { isWorking = false }
            do {
                let reply = try await produce()
                log.info("risposta pronta")
                if case .chat(let prompt, let guides) = reply {
                    try await sendToChat(q, prompt: prompt, guides: guides)
                    return
                }

                endChat()
                switch reply {
                case .message(let text):
                    notice = text
                case .choices(let message, let options):
                    notice = message
                    choices = options
                case .result(let found, let request, let newChart):
                    findings = found
                    chart = newChart
                    guard let request else { return }
                    if case .unavailable(let reason) = assistant.provider.availability {
                        notice = reason
                        return
                    }
                    for try await partial in assistant.explain(request) {
                        answer = partial
                    }
                    if Task.isCancelled { return }
                    log.info("risposta completata: \(self.answer.count) caratteri")
                case .cleanup(let items):
                    cleanupItems = items
                    cleanupSelected = Set(items.filter(\.preselected).map(\.id))
                    if items.isEmpty {
                        notice = L.t("ui.cleanup.none")
                    }
                case .chat:
                    break
                }
            } catch is CancellationError {
            } catch {
                log.error("errore: \(error.localizedDescription, privacy: .public)")
                if isChatting, let last = messages.indices.last, messages[last].role == .assistant {
                    messages[last].text = error.localizedDescription
                    messages[last].isError = true
                } else {
                    notice = error.localizedDescription
                }
            }
        }
    }

    func newConversation() {
        task?.cancel()
        endChat()
        clearResults()
        question = ""
        isWorking = false
    }

    private func sendToChat(_ text: String, prompt: String, guides: [String]) async throws {
        let session = chat ?? assistant.makeChatSession()
        chat = session
        chatGuides = guides
        question = ""
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: "", basedOnGuide: !guides.isEmpty))
        let index = messages.count - 1
        for try await partial in session.send(prompt) {
            messages[index].text = partial
        }
        log.info("chat: risposta di \(self.messages[index].text.count) caratteri")

        if MacHelpChat.answerNeedsGuide(messages[index].text, guides: guides) {
            messages[index].verifiedGuides = guides
        }
    }

    private func endChat() {
        messages = []
        chat = nil
        chatGuides = []
    }

    func toggleCleanup(_ item: CleanupItem) {
        if cleanupSelected.contains(item.id) { cleanupSelected.remove(item.id) } else { cleanupSelected.insert(item.id) }
    }

    func performCleanup() {
        let chosen = selectedCleanupItems
        guard !chosen.isEmpty else { return }
        let result = Cleanup.moveToTrash(chosen)
        lastTrash = result
        let moved = Set(result.moved.map(\.original))
        cleanupItems.removeAll { moved.contains($0.path) }
        cleanupSelected.subtract(moved)
        var text = L.t("ui.cleanup.done", result.moved.count, sizeText(result.bytes))
        if !result.refused.isEmpty {
            text += L.t("ui.cleanup.refused", result.refused.joined(separator: ", "))
        }
        notice = text
        log.info("pulizia: \(result.moved.count) file nel Cestino")
    }

    func undoCleanup() {
        guard let lastTrash else { return }
        let restored = Cleanup.undo(lastTrash)
        self.lastTrash = nil
        notice = L.t("ui.cleanup.restored", restored)

        run(label: L.t("ui.working.cleanup")) { [assistant] in try await assistant.prepare(question: Assistant.cleanupQuestion) }
    }

    func sizeText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func clearResults() {
        speech.stop()
        findings = []
        choices = []
        chart = nil
        chartHover = nil
        answer = ""
        notice = nil
        cleanupItems = []
        cleanupSelected = []
        confirmCleanup = false
    }
}
