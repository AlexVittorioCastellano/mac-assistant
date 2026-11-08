import Foundation

/// Cosa vuole l'utente.
public enum Intent: Sendable, Equatable {
    case slowMac
    case diskSpace
    /// "Controlla il mio Mac": semaforo generale.
    case healthCheck
    /// Caccia alle app sospette (programmi in background, firme).
    case securityScan
    /// Pulizia guidata: proposte di file da togliere.
    case cleanup
    /// Spiegare un processo. `nil` = l'utente non ha indicato quale.
    case process(String?)
    /// Tutto il resto: chat libera su come usare il Mac.
    case chat
}

/// Smista la domanda alla funzione giusta, con regole semplici e prevedibili.
/// Le domande che non riguardano lentezza, processi o disco vanno alla chat.
public enum IntentRouter {
    // Le parole chiave dipendono dalla lingua: stanno nel pacchetto lingua
    // (Languages/*.json, sezione "router"). Regole comuni a tutte le lingue:
    // - si confrontano a INIZIO parola ("disco" non scatta in "ingrandisco");
    // - "strongSlow" vince su "disk" ("il disco è lento" = lentezza);
    // - "health" non deve contenere parole ambigue (es. "Centro di Controllo").
    static var router: LanguagePack.Router { L.current.router }
    static var slowKeywords: [String] { router.slow }
    static var diskKeywords: [String] { router.disk }
    static var healthKeywords: [String] { router.health }
    static var cleanupKeywords: [String] { router.cleanup }
    static var securityKeywords: [String] { router.security }
    static var strongSlowKeywords: [String] { router.strongSlow }
    static var processTriggers: [String] { router.processTriggers }
    static var fillerWords: Set<String> { Set(router.fillerWords) }

    /// - Parameter runningNames: nomi dei processi attivi, per riconoscerli nella frase.
    public static func route(_ question: String, runningNames: [String] = []) -> Intent {
        let text = normalize(question)

        // 1. Nome tra virgolette: «kernel_task», "bird", “mds”.
        if let quoted = quotedName(in: question) { return .process(quoted) }

        let asksAboutProcess = processTriggers.contains { hasStem(text, $0) }
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

    /// Domanda di seguito in una conversazione ("E se non compare?", "Ma dove
    /// lo trovo?", "Non funziona"): continua l'argomento precedente.
    /// "Come creo un nuovo utente?" invece è una domanda nuova.
    public static func isFollowUp(_ question: String) -> Bool {
        let t = normalize(question).trimmingCharacters(in: .whitespaces)
        return router.followUp.contains { t.hasPrefix($0) }
    }

    /// Domanda pratica del tipo "come faccio a…", "cosa faccio se…".
    public static func isHowTo(_ question: String) -> Bool {
        let t = normalize(question)
        return router.howTo.contains { hasStem(t, $0) }
    }

    /// Lentezza o spazio su disco (o nessuno dei due).
    static func topic(of normalized: String) -> Intent? {
        if cleanupKeywords.contains(where: { hasStem(normalized, $0) }) { return .cleanup }
        if securityKeywords.contains(where: { hasStem(normalized, $0) }) { return .securityScan }
        if healthKeywords.contains(where: { hasStem(normalized, $0) }) { return .healthCheck }
        let strongSlow = strongSlowKeywords.contains { hasStem(normalized, $0) }
        let disk = diskKeywords.contains { hasStem(normalized, $0) }
        if disk && !strongSlow { return .diskSpace }
        return isAboutSlowness(normalized) ? .slowMac : nil
    }

    static func isAboutSlowness(_ normalized: String) -> Bool {
        slowKeywords.contains { hasStem(normalized, $0) }
    }

    /// `true` se `stem` compare all'INIZIO di una parola di `text`.
    /// Così "lent" trova "lentissimo", ma "disco" non scatta dentro
    /// "ingrandisco" e "ram" non scatta dentro "programma".
    public static func hasStem(_ text: String, _ stem: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: stem, range: searchRange) {
            if r.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: r.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: L.locale)
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
