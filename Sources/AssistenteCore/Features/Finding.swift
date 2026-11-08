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
    /// Altri consigli legati a questa riga (es. per le voci raggruppate in "Il resto").
    public var moreAdvice: [String] = []
    /// Pallino colorato che collega la riga a una parte di un grafico.
    public var swatch: ChartSwatch?

    public init(id: String, severity: Severity, title: String, advice: String? = nil,
                iconPath: String? = nil, symbol: String? = nil, swatch: ChartSwatch? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.advice = advice
        self.iconPath = iconPath
        self.symbol = symbol
        self.swatch = swatch
    }
}

extension Finding {
    /// I consigli pratici, senza ripetizioni, nell'ordine in cui compaiono.
    public static func advice(from findings: [Finding]) -> [String] {
        var seen = Set<String>()
        return findings.flatMap { [$0.advice].compactMap { $0 } + $0.moreAdvice }
            .filter { seen.insert($0).inserted }
    }
}

/// Il "colore" di una parte di grafico, in modo astratto: il nucleo decide
/// solo la posizione nella palette; i colori veri li sceglie l'interfaccia.
public enum ChartSwatch: Sendable, Equatable, Hashable {
    /// Posizione nella palette categoriale (0 = primo colore), in ordine fisso.
    case series(Int)
    /// Tutto ciò che è stato raggruppato (grigio neutro).
    case rest
}

/// Un intero diviso in parti (es. lo spazio usato, disegnato a ciambella), più
/// (facoltativo) quanto quell'intero pesa su una capacità (es. usato/disco).
public struct SegmentedChart: Sendable, Equatable {
    public struct Segment: Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        public var bytes: UInt64
        public var swatch: ChartSwatch
    }
    /// L'intero diviso dai segmenti (es. lo spazio usato).
    public var totalBytes: UInt64
    public var segments: [Segment]
    /// La capacità di cui `totalBytes` è una parte (es. tutto il disco).
    public var capacityBytes: UInt64?
    /// Gravità del riempimento (per il colore dell'indicatore).
    public var level: Finding.Severity = .ok

    /// "Usati 104,3 GB su 926,3 GB (11%)"
    public var capacitySummary: String? {
        guard let capacityBytes, capacityBytes > 0 else { return nil }
        let share = Double(totalBytes) / Double(capacityBytes) * 100
        return "Usati \(Fmt.size(totalBytes)) su \(Fmt.size(capacityBytes)) (\(Fmt.percent(share)))"
    }

    /// "104,3 GB": il totale, per il centro del grafico.
    public var totalLabel: String { Fmt.size(totalBytes) }

    /// "24,3 GB": quantità di una parte.
    public func amount(of s: Segment) -> String { Fmt.size(s.bytes) }

    /// "35%": quota di una parte sul totale.
    public func share(of s: Segment) -> String {
        Fmt.percent(totalBytes > 0 ? Double(s.bytes) / Double(totalBytes) * 100 : 0)
    }

    /// Descrizione per VoiceOver e per il passaggio del mouse.
    public func description(of s: Segment) -> String {
        let share = totalBytes > 0 ? Double(s.bytes) / Double(totalBytes) * 100 : 0
        return "\(s.label): \(Fmt.size(s.bytes)) (\(Fmt.percent(share)))"
    }
}
