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

    /// Chat libera: messaggi e conversazione in corso (che ricorda il contesto).
    var messages: [ChatMessage] = []
    private var chat: (any AIChatSession)?
    /// Guide del turno precedente, ereditate dalle domande di seguito.
    private var chatGuides: [String] = []
    var isChatting: Bool { !messages.isEmpty }

    private let assistant = Assistant()
    private let log = Logger(subsystem: "AssistenteMac", category: "ui")
    private var task: Task<Void, Never>?

    var isOnDevice: Bool { assistant.provider.isOnDevice }

    func ask(_ text: String? = nil) {
        let q = (text ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("ask: \(q, privacy: .public)")
        guard !q.isEmpty else { return }
        question = q

        task?.cancel()
        clearResults()
        isWorking = true

        task = Task {
            defer { isWorking = false }
            do {
                let reply = try await assistant.prepare(question: q, conversationGuides: isChatting ? chatGuides : [])
                log.info("prepare completato")
                if case .chat(let prompt, let guides) = reply {
                    try await sendToChat(q, prompt: prompt, guides: guides)
                    return
                }
                // Una funzione specifica (lentezza, processi, disco) chiude la chat.
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
