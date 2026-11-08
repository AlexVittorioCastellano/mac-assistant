import AssistenteCore
import Observation
import os
import SwiftUI

/// Stato dell'interfaccia. Non contiene logica di sistema o di AI:
/// delega tutto ad `Assistant` (in AssistenteCore).
@MainActor
@Observable
final class AssistantViewModel {
    var question = ""
    var findings: [Finding] = []
    var answer = ""
    var notice: String?
    var isWorking = false

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
        findings = []
        answer = ""
        notice = nil
        isWorking = true

        task = Task {
            defer { isWorking = false }
            do {
                let reply = try await assistant.prepare(question: q)
                log.info("prepare completato")
                switch reply {
                case .message(let text):
                    notice = text
                case .diagnosis(let found, let request):
                    findings = found  // mostrati subito, prima dell'AI
                    if case .unavailable(let reason) = assistant.provider.availability {
                        notice = reason
                        return
                    }
                    for try await partial in assistant.explain(request) {
                        answer = partial
                    }
                    if Task.isCancelled { return }
                    log.info("risposta completata: \(self.answer.count) caratteri")
                }
            } catch is CancellationError {
                // Nuova domanda: nulla da fare.
            } catch {
                log.error("errore: \(error.localizedDescription, privacy: .public)")
                notice = error.localizedDescription
            }
        }
    }
}
