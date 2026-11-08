import Foundation

/// Formattazione numeri all'italiana (virgola decimale).
enum Fmt {
    static let italian = Locale(identifier: "it_IT")

    static func gb(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return value.formatted(.number.precision(.fractionLength(1)).locale(italian)) + " GB"
    }

    /// "2,4 GB" oppure, sotto 1 GB, "350 MB" (più chiaro di "0,3 GB").
    static func size(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 { return gb(bytes) }
        let mb = max(1, Int((Double(bytes) / 1_048_576).rounded()))
        return mb.formatted(.number.locale(italian)) + " MB"
    }

    static func percent(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(italian)) + "%"
    }

    static func days(_ seconds: TimeInterval) -> Int { Int(seconds / 86_400) }
}
