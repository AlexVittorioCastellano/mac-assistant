import Foundation

/// Funzione "Spiegami questo messaggio": l'utente incolla lo screenshot (o il
/// testo) di un avviso o di un errore; l'app lo legge e lo spiega.
///
/// Come per la chat: per i messaggi più comuni di macOS il codice riconosce il
/// messaggio e fornisce una spiegazione verificata; le truffe le riconosce il
/// codice, non l'AI, e vengono segnalate sempre in modo chiaro.
///
/// Gli schemi per riconoscere i messaggi stanno nei pacchetti lingua e si
/// cercano in TUTTE le lingue insieme (una pagina truffa in inglese va
/// riconosciuta anche da chi usa il Mac in italiano); titolo e consiglio
/// arrivano nella lingua dell'utente.
public enum MessageExplainer {

    /// Gravità e icona non dipendono dalla lingua.
    static let meta: [String: (severity: Finding.Severity, symbol: String)] = [
        "scam": (.critical, "exclamationmark.octagon.fill"),
        "unverified": (.warning, "checkmark.shield"),
        "damaged": (.warning, "exclamationmark.triangle"),
        "diskfull": (.warning, "internaldrive"),
        "memory": (.warning, "memorychip"),
        "notresponding": (.info, "hourglass"),
        "panic": (.warning, "arrow.clockwise"),
        "permission": (.info, "hand.raised"),
        "keychain": (.info, "key"),
        "accessory": (.info, "cable.connector"),
        "icloudfull": (.info, "icloud"),
    ]

    /// Ordine fisso dei messaggi (la truffa per prima).
    static let order = ["scam", "unverified", "damaged", "diskfull", "memory", "notresponding",
                        "panic", "permission", "keychain", "accessory", "icloudfull"]

    struct Known {
        let id: String
        let title: String
        let advice: String
        var severity: Finding.Severity { meta[id]?.severity ?? .info }
        var symbol: String { meta[id]?.symbol ?? "info.circle" }
    }

    static func normalize(_ s: String) -> String {
        IntentRouter.normalize(s).replacingOccurrences(of: "\n", with: " ")
    }

    /// Schemi di un messaggio, da tutti i pacchetti lingua.
    static func patterns(for id: String) -> [String] {
        L.packs.values.flatMap { pack in pack.messages.filter { $0.id == id }.flatMap(\.patterns) }
    }

    /// Testi di un messaggio nella lingua corrente (o in inglese).
    static func texts(for id: String) -> (title: String, advice: String) {
        let message = L.current.messages.first { $0.id == id }
            ?? L.packs[L.fallbackCode]?.messages.first { $0.id == id }
        return (message?.title ?? id, message?.advice ?? "")
    }

    static func match(_ text: String) -> [Known] {
        let t = normalize(text)
        return order.filter { id in patterns(for: id).contains { t.contains(normalize($0)) } }
            .map { id in let x = texts(for: id); return Known(id: id, title: x.title, advice: x.advice) }
    }

    public static func isScam(_ text: String) -> Bool {
        match(text).contains { $0.id == "scam" }
    }

    public static func findings(for text: String) -> [Finding] {
        let quoted = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        var result: [Finding] = [Finding(id: "read", severity: .info,
                                         title: L.t("message.read", quoted.count > 180 ? quoted.prefix(180) + "…" : quoted),
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
        var prompt = L.t("message.prompt", text.prefix(1200))
        if let first = matches.first {
            prompt += "\n\n" + L.t("message.prompt.verified", first.title, first.advice)
        }
        if isScam(text) {
            prompt += "\n\n" + L.t("message.prompt.scam")
        }
        prompt += "\n\n" + L.t("message.prompt.end")
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }
}
