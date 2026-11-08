import Foundation

/// Prepara un testo per essere letto ad alta voce dalla sintesi vocale del Mac:
/// i simboli dei tasti diventano parole ("⌥⌘Esc" → "Opzione Comando Esc"),
/// le frecce dei menu diventano "poi", via grassetti e virgolette.
public enum ReadAloud {
    public static func speakable(_ text: String) -> String {
        var t = text
        let keys: [(String, String)] = [
            ("⌘", L.t("speech.cmd")), ("⇧", L.t("speech.shift")),
            ("⌥", L.t("speech.option")), ("⌃", L.t("speech.control")),
        ]
        for (symbol, word) in keys { t = t.replacingOccurrences(of: symbol, with: " \(word) ") }
        t = t.replacingOccurrences(of: "→", with: L.t("speech.then"))
        for mark in ["**", "«", "»", "“", "”", "`"] { t = t.replacingOccurrences(of: mark, with: "") }
        t = t.replacingOccurrences(of: "\n", with: ". ")
        // Spazi doppi lasciati dalle sostituzioni.
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.replacingOccurrences(of: " ,", with: ",").trimmingCharacters(in: .whitespaces)
    }

    /// Il testo da leggere per un risultato: voci, spiegazione e consigli.
    public static func text(findings: [Finding], answer: String) -> String {
        let parts = findings.map(\.title) + [answer] + Finding.advice(from: findings)
        return speakable(parts.filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

/// Riepilogo dello stato del Mac da mandare a chi ti aiuta (un figlio, un
/// tecnico). L'app lo prepara e basta: copiarlo e mandarlo lo decide l'utente.
/// Non contiene nomi di file né dati personali.
public enum HelperReport {
    public struct MacInfo: Sendable {
        public var chip: String
        public var memory: String
        public var macOS: String

        public static func current() -> MacInfo {
            var size = 0
            sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
            var buffer = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            let chip = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return MacInfo(chip: chip.isEmpty ? "Mac" : chip,
                           memory: Fmt.gb(ProcessInfo.processInfo.physicalMemory).replacingOccurrences(of: ",0", with: "").replacingOccurrences(of: ".0", with: ""),
                           macOS: "\(v.majorVersion).\(v.minorVersion)")
        }
    }

    static func mark(_ s: Finding.Severity) -> String {
        switch s {
        case .ok: "✅"
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .critical: "❌"
        }
    }

    /// `findings`: il risultato del controllo generale (la prima riga è il semaforo).
    public static func text(findings: [Finding], info: MacInfo = .current(), date: Date = Date()) -> String {
        let day = date.formatted(.dateTime.day().month(.wide).year().locale(L.locale))
        var lines = [L.t("report.title", day), "", L.t("report.mac", info.chip, info.memory, info.macOS)]
        if let overall = findings.first(where: { $0.id == "overall" }) {
            lines += ["", L.t("report.status", overall.title)]
        }
        lines.append("")
        for f in findings where f.id != "overall" {
            lines.append("\(mark(f.severity)) \(f.title)")
        }
        lines += ["", L.t("report.footer")]
        return lines.joined(separator: "\n")
    }
}
