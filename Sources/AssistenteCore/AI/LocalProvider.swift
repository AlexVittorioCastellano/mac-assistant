import Foundation
import FoundationModels

/// Provider on-device basato sul framework Foundation Models di Apple.
///
/// Requisiti: Mac con Apple Silicon, Apple Intelligence attiva.
/// Privacy: tutto avviene sul Mac, niente viene inviato in rete.
public struct LocalProvider: AIProvider {
    public init() {}

    public var displayName: String { L.t("error.provider.name") }
    public var isOnDevice: Bool { true }

    public var availability: ProviderAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            guard model.supportsLocale(L.locale) else {
                return .unavailable(L.t("error.ai.noLanguage"))
            }
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(L.t("error.ai.notEligible"))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(L.t("error.ai.notEnabled"))
        case .unavailable(.modelNotReady):
            return .unavailable(L.t("error.ai.notReady"))
        case .unavailable:
            return .unavailable(L.t("error.ai.unavailable"))
        }
    }

    public func streamResponse(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Una sessione nuova per ogni richiesta: le domande v1 sono
                    // indipendenti e così il contesto (limitato) resta piccolo.
                    //
                    // Guardrail "permissive": con quelle predefinite il filtro
                    // sull'output bloccava a caso risposte innocue (es. "il tuo Mac
                    // funziona bene"). I nostri prompt contengono solo dati di sistema
                    // e i filtri di sicurezza di base restano comunque attivi.
                    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                    let session = LanguageModelSession(model: model, instructions: request.instructions)
                    // Temperatura bassa: vogliamo spiegazioni fedeli ai dati, non creative.
                    let options = GenerationOptions(temperature: 0.3)
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.friendly(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func makeChatSession(instructions: String) -> any AIChatSession {
        LocalChatSession(instructions: instructions)
    }

    /// Guardrail "permissive" (vedi `streamResponse`).
    static func makeSession(instructions: String) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }

    /// Traduce gli errori del framework in messaggi semplici.
    static func friendly(_ error: Error) -> Error {
        if error is SystemLanguageModel.Error {
            return AIError(L.t("error.ai.notReadyShort"))
        }
        guard let error = error as? LanguageModelError else { return error }
        switch error {
        case .contextSizeExceeded:
            return AIError(L.t("error.ai.tooLong"))
        case .guardrailViolation, .refusal:
            return AIError(L.t("error.ai.refused"))
        case .unsupportedLanguageOrLocale:
            return AIError(L.t("error.ai.unsupportedLanguage"))
        case .rateLimited:
            return AIError(L.t("error.ai.busy"))
        case .timeout:
            return AIError(L.t("error.ai.timeout"))
        default:
            return AIError(L.t("error.ai.failed"))
        }
    }
}

/// Conversazione on-device. Il modello ha un contesto limitato (qualche
/// migliaio di parole): quando si riempie, la conversazione ricomincia da capo
/// e lo diciamo all'utente.
actor LocalChatSession: AIChatSession {
    private let instructions: String
    private var session: LanguageModelSession

    init(instructions: String) {
        self.instructions = instructions
        self.session = LocalProvider.makeSession(instructions: instructions)
    }

    nonisolated func send(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(prompt, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ prompt: String, _ continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        do {
            // "Greedy": sceglie sempre la parola più probabile. Nelle prove copiava
            // le scorciatoie dalla guida senza errori (6/6, contro 5/6 con
            // temperatura 0.3) e dà la stessa risposta alla stessa domanda.
            let options = GenerationOptions(samplingMode: .greedy)
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                continuation.yield(snapshot.content)
            }
            continuation.finish()
        } catch LanguageModelError.contextSizeExceeded {
            // Conversazione troppo lunga: ripartiamo da zero.
            session = LocalProvider.makeSession(instructions: instructions)
            continuation.finish(throwing: AIError(
                L.t("error.ai.chatTooLong")))
        } catch {
            continuation.finish(throwing: LocalProvider.friendly(error))
        }
    }
}
