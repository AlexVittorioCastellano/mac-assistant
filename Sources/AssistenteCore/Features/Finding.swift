import Foundation

/// Un'informazione mostrata all'utente (problema, conferma o verdetto),
/// in parole semplici, con l'eventuale consiglio pratico.
public struct Finding: Sendable, Equatable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        case ok, info, warning, critical
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String
    public var severity: Severity
    public var title: String
    /// Cosa può fare l'utente. Scritto dal codice, non dall'AI:
    /// così i consigli sono sempre corretti e sicuri.
    public var advice: String?
    /// Icona facoltativa: file o cartella di cui mostrare l'icona del Finder
    /// (es. un'app, la cartella Download). Ha la precedenza su `symbol`.
    public var iconPath: String?
    /// Icona facoltativa: nome di un simbolo SF (es. "sparkles").
    /// Senza icone, l'interfaccia usa quella della gravità.
    public var symbol: String?

    public init(id: String, severity: Severity, title: String, advice: String? = nil,
                iconPath: String? = nil, symbol: String? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.advice = advice
        self.iconPath = iconPath
        self.symbol = symbol
    }
}

extension Finding {
    /// I consigli pratici, senza ripetizioni, nell'ordine in cui compaiono.
    public static func advice(from findings: [Finding]) -> [String] {
        var seen = Set<String>()
        return findings.compactMap(\.advice).filter { seen.insert($0).inserted }
    }
}
