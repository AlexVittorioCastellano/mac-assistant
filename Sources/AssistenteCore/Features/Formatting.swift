import Foundation

enum Fmt {
    static var locale: Locale { L.locale }

    static func gb(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " GB"
    }

    static func size(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 { return gb(bytes) }
        let mb = max(1, Int((Double(bytes) / 1_048_576).rounded()))
        return mb.formatted(.number.locale(locale)) + " MB"
    }

    static func percent(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(locale)) + "%"
    }

    static func days(_ seconds: TimeInterval) -> Int { Int(seconds / 86_400) }
}
