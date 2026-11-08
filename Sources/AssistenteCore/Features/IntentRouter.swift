import Foundation

/// Cosa vuole l'utente.
public enum Intent: Sendable, Equatable {
    case slowMac
    case diskSpace
    /// Spiegare un processo. `nil` = l'utente non ha indicato quale.
    case process(String?)
    /// Tutto il resto: chat libera su come usare il Mac.
    case chat
}

/// Smista la domanda alla funzione giusta, con regole semplici e prevedibili.
/// Le domande che non riguardano lentezza, processi o disco vanno alla chat.
public enum IntentRouter {
    static let slowKeywords = [
        "lento", "lenta", "lentezza", "rallent", "bloccat", "si blocca", "impalla",
        "ventol", "scalda", "caldo", "cpu", "processore", "ram", "memoria", "pesante",
        "girella", "rotella", "pallina",
    ]

    static let diskKeywords = [
        // Non "istantanea": "istantanea dello schermo" è uno screenshot.
        "spazio", "disco", "archiviazione", "dati di sistema", "storage", "snapshot",
        "istantanee locali", "gb liber", "pieno", "piena", "occupa",
    ]

    /// Parole che indicano chiaramente la lentezza (vincono su "disco"):
    /// "il disco è lento" riguarda la velocità, non lo spazio.
    /// Anche "RAM", "CPU" e "processore" indicano la lentezza: "quale app occupa
    /// più RAM" non riguarda il disco. "Memoria" invece è ambigua in italiano
    /// ("memoria piena" di solito vuol dire disco pieno).
    static let strongSlowKeywords = ["lento", "lenta", "lentezza", "rallent", "bloccat", "si blocca",
                                     "ventol", "scalda", "caldo", "ram", "cpu", "processore"]

    /// Frasi che indicano una domanda su un processo.
    static let processTriggers = [
        "cos'e", "cosa e", "cos e", "che cos", "cosa fa", "a cosa serve", "che fa",
        "processo", "chiudere", "chiuderlo", "chiuderla", "posso chiudere", "che roba",
    ]

    /// Parole da togliere per trovare il nome del processo nella frase.
    static let fillerWords: Set<String> = [
        "il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "questo", "questa",
        "quel", "quello", "quella", "processo", "programma", "app", "applicazione",
        "si", "puo", "posso", "chiudere", "chiuderlo", "chiuderla", "e", "che", "di",
        "sul", "mio", "mac", "serve", "a", "cosa", "fa", "cos", "roba",
    ]

    /// - Parameter runningNames: nomi dei processi attivi, per riconoscerli nella frase.
    public static func route(_ question: String, runningNames: [String] = []) -> Intent {
        let text = normalize(question)

        // 1. Nome tra virgolette: «kernel_task», "bird", “mds”.
        if let quoted = quotedName(in: question) { return .process(quoted) }

        let asksAboutProcess = processTriggers.contains { text.contains($0) }
        if asksAboutProcess {
            // 2. Un processo attivo nominato nella frase (il nome più lungo vince).
            if let name = runningName(in: text, among: runningNames) {
                // "Brave Browser Helper" contiene il nome attivo "Brave Browser", ma
                // l'utente chiede dell'Helper: se ha scritto di più, teniamo il suo testo.
                if let candidate = candidateName(in: question),
                   normalize(candidate).count > name.count,
                   containsWord(normalize(candidate), normalize(name)) {
                    return .process(candidate)
                }
                return .process(name)
            }
            // 3. Domande tipo "cosa fa il Mac quando è lento" o "cos'è Dati di
            //    sistema" non riguardano un processo.
            if let topic = topic(of: text) { return topic }
            // 4. Altrimenti, il nome è quello che resta tolte le parole di contorno.
            return .process(candidateName(in: question))
        }
        return topic(of: text) ?? .chat
    }

    /// Lentezza o spazio su disco (o nessuno dei due).
    static func topic(of normalized: String) -> Intent? {
        let strongSlow = strongSlowKeywords.contains { normalized.contains($0) }
        let disk = diskKeywords.contains { normalized.contains($0) }
        if disk && !strongSlow { return .diskSpace }
        return isAboutSlowness(normalized) ? .slowMac : nil
    }

    static func isAboutSlowness(_ normalized: String) -> Bool {
        slowKeywords.contains { normalized.contains($0) }
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.italian)
    }

    static func quotedName(in s: String) -> String? {
        for (open, close) in [("«", "»"), ("“", "”"), ("\"", "\"")] {
            guard let a = s.range(of: open),
                  let b = s.range(of: close, range: a.upperBound..<s.endIndex) else { continue }
            let name = s[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// Cerca nella frase il nome intero di un processo attivo (almeno 3 lettere).
    static func runningName(in normalizedText: String, among names: [String]) -> String? {
        names
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
            .first { containsWord(normalizedText, normalize($0)) }
    }

    /// `true` se `word` compare in `text` come parola intera.
    static func containsWord(_ text: String, _ word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: word, range: searchRange) {
            let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            let isBoundary: (Character?) -> Bool = { c in
                guard let c else { return true }
                return !(c.isLetter || c.isNumber || c == "_")
            }
            if isBoundary(before) && isBoundary(after) { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }

    /// "Cos'è mds_stores?" -> "mds_stores". `nil` se non resta niente
    /// (es. "Cos'è questo processo?").
    static func candidateName(in question: String) -> String? {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "?!.,;:'’"))
        let words = question.components(separatedBy: separators).filter { !$0.isEmpty }
        let kept = words.filter { !fillerWords.contains(normalize($0)) }
        return kept.isEmpty ? nil : kept.joined(separator: " ")
    }
}
