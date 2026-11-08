import AssistenteCore
import Observation
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
    private var task: Task<Void, Never>?

    var isOnDevice: Bool { assistant.provider.isOnDevice }

    func ask(_ text: String? = nil) {
        let q = (text ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
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
                switch try await assistant.prepare(question: q) {
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
                }
            } catch is CancellationError {
                // Nuova domanda: nulla da fare.
            } catch {
                notice = error.localizedDescription
            }
        }
    }
}
