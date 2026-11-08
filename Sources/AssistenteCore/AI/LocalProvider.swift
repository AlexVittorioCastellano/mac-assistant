import Foundation
import FoundationModels

/// Provider on-device basato sul framework Foundation Models di Apple.
///
/// Requisiti: Mac con Apple Silicon, Apple Intelligence attiva.
/// Privacy: tutto avviene sul Mac, niente viene inviato in rete.
public struct LocalProvider: AIProvider {
    public init() {}

    public var displayName: String { "Sul tuo Mac" }
    public var isOnDevice: Bool { true }

    public var availability: ProviderAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            guard model.supportsLocale(Locale(identifier: "it_IT")) else {
                return .unavailable("Il modello sul Mac non supporta l'italiano.")
            }
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Questo Mac non supporta Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Attiva Apple Intelligence in Impostazioni di Sistema per avere le spiegazioni.")
        case .unavailable(.modelNotReady):
            return .unavailable("Il modello di Apple Intelligence si sta ancora scaricando. Riprova tra poco.")
        case .unavailable:
            return .unavailable("Apple Intelligence non è disponibile in questo momento.")
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
            return AIError("Il modello non è ancora pronto. Riprova tra poco.")
        }
        guard let error = error as? LanguageModelError else { return error }
        switch error {
        case .contextSizeExceeded:
            return AIError("La richiesta è troppo lunga per il modello sul Mac.")
        case .guardrailViolation, .refusal:
            return AIError("Questa volta non sono riuscito a scrivere una spiegazione, ma qui sopra trovi cosa ho controllato.")
        case .unsupportedLanguageOrLocale:
            return AIError("Il modello non supporta la lingua impostata sul Mac.")
        case .rateLimited:
            return AIError("Il modello è occupato. Riprova tra qualche secondo.")
        case .timeout:
            return AIError("Il modello ci sta mettendo troppo. Riprova.")
        default:
            return AIError("Non sono riuscito a generare una risposta.")
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
                "La conversazione è diventata troppo lunga per il modello sul Mac, quindi ne ho iniziata una nuova. Ripeti pure la domanda."))
        } catch {
            continuation.finish(throwing: LocalProvider.friendly(error))
        }
    }
}
