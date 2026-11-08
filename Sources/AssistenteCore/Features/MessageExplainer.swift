import Foundation

/// Funzione "Spiegami questo messaggio": l'utente incolla lo screenshot (o il
/// testo) di un avviso o di un errore; l'app lo legge e lo spiega.
///
/// Come per la chat: per i messaggi più comuni di macOS il codice riconosce il
/// messaggio e fornisce una guida verificata; le truffe le riconosce il codice,
/// non l'AI, e vengono segnalate sempre in modo chiaro.
public enum MessageExplainer {

    struct Known {
        let id: String
        /// Basta che il testo contenga una di queste frasi (minuscole, senza accenti).
        let patterns: [String]
        let severity: Finding.Severity
        let title: String
        let advice: String
        let symbol: String
    }

    static let known: [Known] = [
        Known(id: "scam",
              patterns: ["il tuo mac e infetto", "il tuo computer e infetto", "your mac is infected", "your computer is infected",
                         "virus rilevat", "virus detected", "chiama il supporto", "call apple support", "call support",
                         "contatta il supporto apple al", "numero verde", "toll free", "il tuo mac e bloccato", "your mac is locked",
                         "il tuo iphone e stato hackerato", "il tuo mac e stato hackerato", "hacked"],
              severity: .critical,
              title: "Quasi certamente è una TRUFFA",
              advice: "macOS non mostra mai avvisi di virus dentro il browser e Apple non ti chiede di chiamare un numero. Non chiamare, non scaricare nulla e non dare password: chiudi la scheda con ⌘W (se non si chiude, esci dal browser con ⌥⌘Esc).",
              symbol: "exclamationmark.octagon.fill"),
        Known(id: "unverified",
              patterns: ["sviluppatore non puo essere verificato", "developer cannot be verified", "non puo verificare",
                         "could not verify", "apple cannot check it for malicious", "non e possibile verificare la presenza di malware",
                         "free of malware", "privo di malware"],
              severity: .warning,
              title: "È un controllo di sicurezza di macOS sulle app scaricate da Internet",
              advice: "Se l'app viene da un sito ufficiale di cui ti fidi, puoi aprirla da Impostazioni di Sistema → Privacy e sicurezza: scorri in basso e premi «Apri comunque». Se non sai da dove viene, eliminala.",
              symbol: "checkmark.shield"),
        Known(id: "damaged",
              patterns: ["e danneggiat", "is damaged and can", "danneggiato e non puo essere aperto"],
              severity: .warning,
              title: "macOS blocca un'app che risulta danneggiata o modificata",
              advice: "Elimina l'app e scaricala di nuovo dal sito ufficiale o dall'App Store. Non usare comandi trovati online per forzarne l'apertura.",
              symbol: "exclamationmark.triangle"),
        Known(id: "diskfull",
              patterns: ["disco di avvio e quasi pieno", "startup disk is almost full", "disco di avvio e pieno", "spazio su disco insufficiente",
                         "not enough disk space", "spazio di archiviazione insufficiente"],
              severity: .warning,
              title: "Lo spazio sul disco sta finendo",
              advice: "Premi «Spazio disco» in questa app per vedere cosa occupa più spazio.",
              symbol: "internaldrive"),
        Known(id: "memory",
              patterns: ["esaurito la memoria", "run out of application memory", "memoria delle applicazioni"],
              severity: .warning,
              title: "Il Mac ha finito la memoria per le app",
              advice: "Chiudi le app e le schede del browser che non usi. Se succede spesso, premi «Mac lento» in questa app.",
              symbol: "memorychip"),
        Known(id: "notresponding",
              patterns: ["non risponde", "not responding", "uscita forzata"],
              severity: .info,
              title: "Un'app si è bloccata",
              advice: "Premi ⌥⌘Esc, scegli l'app e clicca «Uscita forzata». Le modifiche non salvate in quell'app si perdono.",
              symbol: "hourglass"),
        Known(id: "panic",
              patterns: ["riavviato a causa di un problema", "restarted because of a problem", "si e riavviato perche si e verificato un problema"],
              severity: .warning,
              title: "Il Mac si è riavviato da solo per un errore",
              advice: "Se è successo una volta sola, non preoccuparti. Se si ripete: installa gli aggiornamenti di macOS e delle app, scollega gli accessori e, se continua, rivolgiti all'assistenza Apple.",
              symbol: "arrow.clockwise"),
        Known(id: "permission",
              patterns: ["vorrebbe accedere", "would like to access", "desidera accedere", "vorrebbe registrare", "would like to record",
                         "vorrebbe controllare", "would like to control", "vuole accedere"],
              severity: .info,
              title: "Un'app ti chiede un permesso",
              advice: "Consenti solo se conosci l'app e il permesso ha senso per quello che fa (es. una app per videochiamate e la fotocamera). Puoi cambiare idea in Impostazioni di Sistema → Privacy e sicurezza.",
              symbol: "hand.raised"),
        Known(id: "keychain",
              patterns: ["portachiavi", "keychain"],
              severity: .info,
              title: "Il portachiavi chiede la password",
              advice: "Il portachiavi custodisce le tue password: di solito chiede la stessa password che usi per accedere al Mac. Inseriscila solo se la richiesta arriva da un'app che stai usando.",
              symbol: "key"),
        Known(id: "accessory",
              patterns: ["consentire all'accessorio", "allow accessory to connect", "accessorio di connettersi"],
              severity: .info,
              title: "macOS chiede se fidarsi di un accessorio collegato",
              advice: "Consenti se hai appena collegato tu quell'accessorio (chiavetta, disco, adattatore). Se non hai collegato nulla, rifiuta.",
              symbol: "cable.connector"),
        Known(id: "icloudfull",
              patterns: ["spazio icloud", "icloud storage is full", "archiviazione icloud", "icloud e pieno"],
              severity: .info,
              title: "Lo spazio di iCloud è pieno (è online, non sul Mac)",
              advice: "Puoi vedere cosa occupa iCloud in Impostazioni di Sistema → il tuo nome → iCloud. Liberare spazio sul Mac non risolve questo messaggio.",
              symbol: "icloud"),
    ]

    static func normalize(_ s: String) -> String {
        IntentRouter.normalize(s).replacingOccurrences(of: "\n", with: " ")
    }

    static func match(_ text: String) -> [Known] {
        let t = normalize(text)
        return known.filter { k in k.patterns.contains { t.contains($0) } }
    }

    public static func isScam(_ text: String) -> Bool {
        match(text).contains { $0.id == "scam" }
    }

    public static func findings(for text: String) -> [Finding] {
        let quoted = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        var result: [Finding] = [Finding(id: "read", severity: .info,
                                         title: "Testo letto: «\(quoted.count > 180 ? quoted.prefix(180) + "…" : quoted)»",
                                         symbol: "text.viewfinder")]
        let matches = match(text)
        // Una truffa vince su tutto: niente altri consigli che potrebbero confondere.
        let shown = matches.contains { $0.id == "scam" } ? matches.filter { $0.id == "scam" } : matches
        for k in shown.prefix(2) {
            result.append(Finding(id: k.id, severity: k.severity, title: k.title, advice: k.advice, symbol: k.symbol))
        }
        return result
    }

    public static func request(for text: String) -> AIRequest {
        let matches = match(text)
        var prompt = """
        L'utente ha ricevuto questo messaggio sul Mac e chiede cosa significa:
        «\(text.prefix(1200))»
        """
        if let first = matches.first {
            prompt += "\n\nInformazione verificata: \(first.title). \(first.advice)"
        }
        if isScam(text) {
            prompt += "\n\nÈ una truffa: dillo chiaramente all'utente e non dare nessuna istruzione per seguire il messaggio."
        }
        prompt += """


        Spiega in 2 o 3 frasi semplici cosa significa il messaggio. Non dare consigli in elenco: \
        li mostra già l'app. Non suggerire mai comandi nel Terminale e non suggerire di disattivare \
        protezioni di sicurezza. Se il testo è incomprensibile o non è un messaggio del Mac, dillo.
        """
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }
}
