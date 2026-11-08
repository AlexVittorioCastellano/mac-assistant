import Foundation

public struct Finding: Sendable, Equatable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        case ok, info, warning, critical
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String
    public var severity: Severity
    public var title: String

    public var advice: String?

    public var iconPath: String?

    public var symbol: String?

    public var moreAdvice: [String] = []

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
    public static func advice(from findings: [Finding]) -> [String] {
        var seen = Set<String>()
        return findings.flatMap { [$0.advice].compactMap { $0 } + $0.moreAdvice }
            .filter { seen.insert($0).inserted }
    }
}

public enum ChartSwatch: Sendable, Equatable, Hashable {
    case series(Int)

    case rest
}

public struct SegmentedChart: Sendable, Equatable {
    public struct Segment: Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        public var bytes: UInt64
        public var swatch: ChartSwatch
    }

    public var totalBytes: UInt64
    public var segments: [Segment]

    public var capacityBytes: UInt64?

    public var level: Finding.Severity = .ok

    public var capacitySummary: String? {
        guard let capacityBytes, capacityBytes > 0 else { return nil }
        let share = Double(totalBytes) / Double(capacityBytes) * 100
        return L.t("ui.chart.capacity", Fmt.size(totalBytes), Fmt.size(capacityBytes), Fmt.percent(share))
    }

    public var totalLabel: String { Fmt.size(totalBytes) }

    public func amount(of s: Segment) -> String { Fmt.size(s.bytes) }

    public func share(of s: Segment) -> String {
        Fmt.percent(totalBytes > 0 ? Double(s.bytes) / Double(totalBytes) * 100 : 0)
    }

    public func description(of s: Segment) -> String {
        let share = totalBytes > 0 ? Double(s.bytes) / Double(totalBytes) * 100 : 0
        return "\(s.label): \(Fmt.size(s.bytes)) (\(Fmt.percent(share)))"
    }
}
