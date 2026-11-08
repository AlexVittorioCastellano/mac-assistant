import Foundation

/// Una richiesta al "cervello" AI.
///
/// - `instructions`: il ruolo e le regole (tono, lingua, limiti).
/// - `prompt`: la domanda dell'utente arricchita con i dati del Mac.
public struct AIRequest: Sendable, Equatable {
    public var instructions: String
    public var prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}

/// Se il provider è pronto a rispondere, e in caso contrario perché.
public enum ProviderAvailability: Sendable, Equatable {
    case available
    /// Il messaggio è già in italiano e pronto da mostrare all'utente.
    case unavailable(String)
}

/// Errori comprensibili per l'utente (messaggi in italiano).
public struct AIError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Il punto di accesso unico all'intelligenza artificiale.
///
/// Il resto dell'app parla SOLO con questo protocollo, mai direttamente con
/// un modello specifico. Così si possono aggiungere altri provider senza
/// toccare l'interfaccia o la raccolta dati.
///
/// Implementazioni:
/// - `LocalProvider` (v1): modello on-device di Apple. Nessun dato lascia il Mac.
/// - `CloudProvider` (futuro, NON in questo repository per ora): parlerà con
///   un backend separato dopo il login dell'utente (es. Accedi con Apple).
///   Il client non conterrà mai chiavi API: autenticazione, abbonamento e
///   limiti d'uso saranno verificati dal server. L'URL del backend andrà in
///   una configurazione esclusa da git.
public protocol AIProvider: Sendable {
    /// Nome mostrato all'utente (es. "Sul tuo Mac").
    var displayName: String { get }

    /// `true` se i dati restano sul Mac. L'interfaccia lo usa per informare l'utente.
    var isOnDevice: Bool { get }

    var availability: ProviderAvailability { get }

    /// Genera una risposta in streaming. Ogni elemento è il testo COMPLETO
    /// generato fino a quel momento (non solo l'ultimo pezzo), così
    /// l'interfaccia può semplicemente sostituire il testo mostrato.
    func streamResponse(to request: AIRequest) -> AsyncThrowingStream<String, Error>

    /// Crea una conversazione che ricorda i messaggi precedenti (chat libera).
    func makeChatSession(instructions: String) -> any AIChatSession
}

/// Una conversazione a più turni: ogni `send` vede anche i messaggi precedenti.
public protocol AIChatSession: Sendable {
    /// Come `AIProvider.streamResponse`: ogni elemento è il testo completo
    /// della risposta generato fino a quel momento.
    func send(_ prompt: String) -> AsyncThrowingStream<String, Error>
}

extension AIProvider {
    /// Comodità: attende la risposta completa.
    public func respond(to request: AIRequest) async throws -> String {
        var last = ""
        for try await partial in streamResponse(to: request) { last = partial }
        return last
    }
}
