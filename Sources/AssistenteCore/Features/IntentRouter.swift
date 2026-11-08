import Foundation

/// Cosa vuole l'utente. Si amplierà con le prossime funzioni.
public enum Intent: Sendable, Equatable {
    case slowMac
    case notYetSupported
}

/// Smista la domanda alla funzione giusta, con semplici parole chiave.
/// Volutamente semplice e prevedibile; con la chat libera (funzione 4)
/// le domande non riconosciute andranno al modello.
public enum IntentRouter {
    static let slowKeywords = [
        "lento", "lenta", "lentezza", "rallent", "bloccat", "si blocca", "impalla",
        "ventol", "scalda", "caldo", "cpu", "processore", "ram", "memoria", "pesante",
        "girella", "rotella", "pallina",
    ]

    public static func route(_ question: String) -> Intent {
        let text = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.italian)
        return slowKeywords.contains { text.contains($0) } ? .slowMac : .notYetSupported
    }
}
