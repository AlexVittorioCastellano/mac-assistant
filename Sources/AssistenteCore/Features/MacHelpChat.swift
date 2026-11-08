import Foundation

/// Funzione 4: chat libera su come fare cose sul Mac.
///
/// Il modello on-device è piccolo e può sbagliare scorciatoie o percorsi di
/// menu. Per gli argomenti più comuni gli passiamo una "guida" verificata
/// (`MacHowTo`), scelta dal codice in base alle parole della domanda.
public enum MacHelpChat {

    public static var instructions: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Prompts.base + "\n\n" + L.t("chat.instructions", version.majorVersion)
    }

    /// Le guide verificate pertinenti alla domanda.
    public static func guides(for question: String) -> [String] {
        MacHowTo.matching(question)
    }

    /// Il messaggio da inviare al modello: la domanda, più le guide pertinenti.
    public static func prompt(for question: String) -> String {
        prompt(for: question, guides: guides(for: question))
    }

    /// Come sopra, con guide già scelte (es. ereditate dal turno precedente).
    public static func prompt(for question: String, guides: [String]) -> String {
        guard !guides.isEmpty else {
            // Senza guida il modello piccolo tende a inventare menu e pulsanti
            // con sicurezza: gli chiediamo di essere prudente.
            return question + "\n\n" + L.t("chat.noGuide")
        }
        return question + "\n\n" + L.t("chat.guideHeader") + "\n"
            + guides.map { "- \($0)" }.joined(separator: "\n")
    }
}

extension MacHelpChat {
    /// Rete di sicurezza: `true` se la risposta contiene una scorciatoia da
    /// tastiera che non compare nelle guide verificate (es. "⌘ e 3" invece di
    /// "⌘⇧3"). In quel caso l'interfaccia mostra anche la guida esatta.
    public static func answerNeedsGuide(_ answer: String, guides: [String]) -> Bool {
        guard !guides.isEmpty else { return false }
        // Ammesse: le scorciatoie delle guide e quelle delle istruzioni (Spotlight).
        // Un simbolo da solo ("⌘" senza tasto) di norma non è una scorciatoia valida.
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        // Eccezione: se la guida stessa lo scrive da solo ("tieni premuto ⌘ e premi Tab").
        let allowed = Set(guides.flatMap(shortcuts)
            + shortcuts(in: instructions).filter { !$0.allSatisfy(modifiers.contains) })
        return shortcuts(in: answer).contains { !allowed.contains($0) }
    }

    /// Scorciatoie in un testo: simboli dei tasti seguiti dal tasto
    /// (es. "⌘⇧4", "⌥⌘Esc"; "⌘" da solo se manca il tasto).
    static func shortcuts(in text: String) -> [String] {
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        let stops: Set<Character> = [" ", "\n", ".", ",", ";", ":", ")", "»", "*", "("]
        var result: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard modifiers.contains(text[i]) else { i = text.index(after: i); continue }
            var j = i
            while j < text.endIndex, modifiers.contains(text[j]) { j = text.index(after: j) }
            // Il primo carattere dopo i simboli è il tasto, anche se è un segno
            // di punteggiatura (es. "⌘⇧." per i file nascosti). Ma dopo un solo
            // simbolo la punteggiatura è la fine della frase ("premi il tasto ⌘.").
            let modifierCount = text.distance(from: i, to: j)
            if j < text.endIndex, !text[j].isWhitespace,
               !(modifierCount == 1 && stops.contains(text[j])) {
                j = text.index(after: j)
            }
            while j < text.endIndex, !stops.contains(text[j]) { j = text.index(after: j) }
            // "⌘ Spazio": il tasto può essere scritto dopo uno spazio.
            let spaceKey = " " + L.t("chat.spaceKey")
            if text[i..<j].allSatisfy(modifiers.contains), text[j...].hasPrefix(spaceKey) {
                j = text.index(j, offsetBy: spaceKey.count)
            }
            result.append(String(text[i..<j]))
            i = j
        }
        return result
    }
}

/// Istruzioni brevi e verificate per le domande più comuni, nella lingua
/// corrente (pacchetti lingua, sezione "guides").
/// Contributi benvenuti! Regole: solo cose certe e valide da diverse versioni
/// di macOS, con i nomi ESATTI dei menu in quella lingua; parole chiave senza
/// accenti e in minuscolo. Una parola chiave con "+" richiede tutte le parti,
/// in qualunque ordine (es. "iphone+file").
public enum MacHowTo {
    /// Le guide stanno nel pacchetto lingua (sezione "guides").
    static var entries: [LanguagePack.Guide] { L.current.guides }

    /// Le guide pertinenti alla domanda (al massimo 2, per non riempire il contesto).
    static func matching(_ question: String) -> [String] {
        let text = IntentRouter.normalize(question)
        func matches(_ keyword: String) -> Bool {
            keyword.split(separator: "+").allSatisfy { IntentRouter.hasStem(text, String($0)) }
        }
        return Array(entries.filter { $0.keywords.contains(where: matches) }.prefix(2).map(\.text))
    }
}
