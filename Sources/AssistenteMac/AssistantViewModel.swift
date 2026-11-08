import AppKit
import AssistenteCore
import Observation
import os
import SwiftUI

/// Un messaggio della chat libera.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var isError = false
    /// Guida verificata da mostrare sotto la risposta (vedi `answerNeedsGuide`).
    var verifiedGuides: [String] = []
    /// La risposta si basa su una guida verificata (mostriamo un segno di spunta).
    var basedOnGuide = false
}

/// Stato dell'interfaccia. Non contiene logica di sistema o di AI:
/// delega tutto ad `Assistant` (in AssistenteCore).
@MainActor
@Observable
final class AssistantViewModel {
    var question = ""
    var findings: [Finding] = []
    var choices: [Choice] = []
    var chart: SegmentedChart?
    /// Punto del grafico sotto il mouse. Sta qui e non in @State perché in
    /// macOS 27 @State richiede Xcode per compilare.
    var chartHover: Double?
    var answer = ""
    var notice: String?
    var isWorking = false
    /// Testo della rotellina di attesa (dipende da cosa stiamo facendo).
    var workingLabel = "Controllo il Mac…"
    private var lastPrewarm = Date.distantPast

    /// Chat libera: messaggi e conversazione in corso (che ricorda il contesto).
    var messages: [ChatMessage] = []
    private var chat: (any AIChatSession)?
    /// Guide del turno precedente, ereditate dalle domande di seguito.
    private var chatGuides: [String] = []
    var isChatting: Bool { !messages.isEmpty }

    /// Avvisi automatici in background.
    let alerts = AlertService()

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

    /// "Spiega un messaggio": prende dagli appunti uno screenshot (o un file
    /// immagine, o del testo) e lo spiega.
    func explainClipboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            explainImage(data)
        } else if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
                  let data = try? Data(contentsOf: url) {
            explainImage(data)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            question = Assistant.messageQuestion
            run(label: "Leggo il messaggio…") { [assistant] in assistant.explainMessage(text) }
        } else {
            question = Assistant.messageQuestion
            endChat()
            clearResults()
            notice = "Negli appunti non c'è nessun messaggio. Fai uno screenshot del messaggio con ⌃⇧⌘4 "
                + "(tieni premuti Controllo, Maiuscole e Comando, poi premi 4 e seleziona il messaggio) "
                + "e premi di nuovo «Spiega un messaggio». Puoi anche trascinare un'immagine qui."
        }
    }

    /// Immagine trascinata sul riquadro o presa dagli appunti.
    func explainImage(_ data: Data) {
        question = Assistant.messageQuestion
        run(label: "Leggo il messaggio…") { [assistant] in try await assistant.explainMessage(imageData: data) }
        // Se dopo qualche secondo stiamo ancora leggendo, è il primo avvio del
        // riconoscimento del testo: lo diciamo, così l'attesa non sembra un blocco.
        Task {
            try? await Task.sleep(for: .seconds(4))
            if isWorking && findings.isEmpty && notice == nil {
                workingLabel = "Leggo il messaggio… la prima volta può volerci una ventina di secondi"
            }
        }
    }

    /// Prepara in anticipo il riconoscimento del testo (al massimo ogni 5 minuti).
    func prewarmTextRecognition() {
        guard Date().timeIntervalSince(lastPrewarm) > 300 else { return }
        lastPrewarm = Date()
        TextRecognizer.prewarm()
    }

    /// Esegue una richiesta e mostra la risposta (comune a domande e messaggi).
    private func run(label: String = "Controllo il Mac…",
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
                // Una funzione specifica (lentezza, processi, disco…) chiude la chat.
                endChat()
                switch reply {
                case .message(let text):
                    notice = text
                case .choices(let message, let options):
                    notice = message
                    choices = options
                case .result(let found, let request, let newChart):
                    findings = found  // mostrati subito, prima dell'AI
                    chart = newChart
                    guard let request else { return }  // niente spiegazione (es. controllo)
                    if case .unavailable(let reason) = assistant.provider.availability {
                        notice = reason
                        return
                    }
                    for try await partial in assistant.explain(request) {
                        answer = partial
                    }
                    if Task.isCancelled { return }
                    log.info("risposta completata: \(self.answer.count) caratteri")
                case .chat:
                    break  // gestito sopra
                }
            } catch is CancellationError {
                // Nuova domanda: nulla da fare.
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

    /// Inizia da capo la chat libera.
    func newConversation() {
        task?.cancel()
        endChat()
        clearResults()
        question = ""
        isWorking = false
    }

    // MARK: - Privato

    private func sendToChat(_ text: String, prompt: String, guides: [String]) async throws {
        let session = chat ?? assistant.makeChatSession()
        chat = session
        chatGuides = guides
        question = ""  // come nelle app di messaggi: il campo si svuota
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: "", basedOnGuide: !guides.isEmpty))
        let index = messages.count - 1
        for try await partial in session.send(prompt) {
            messages[index].text = partial
        }
        log.info("chat: risposta di \(self.messages[index].text.count) caratteri")
        // Rete di sicurezza: se il modello ha scritto una scorciatoia diversa
        // da quella verificata, mostriamo anche la guida esatta.
        if MacHelpChat.answerNeedsGuide(messages[index].text, guides: guides) {
            messages[index].verifiedGuides = guides
        }
    }

    private func endChat() {
        messages = []
        chat = nil
        chatGuides = []
    }

    private func clearResults() {
        findings = []
        choices = []
        chart = nil
        chartHover = nil
        answer = ""
        notice = nil
    }
}
