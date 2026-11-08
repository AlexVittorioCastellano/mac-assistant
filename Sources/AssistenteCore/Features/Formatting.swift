import Foundation

/// Formattazione numeri all'italiana (virgola decimale).
enum Fmt {
    static let italian = Locale(identifier: "it_IT")

    static func gb(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return value.formatted(.number.precision(.fractionLength(1)).locale(italian)) + " GB"
    }

    static func percent(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(italian)) + "%"
    }

    static func days(_ seconds: TimeInterval) -> Int { Int(seconds / 86_400) }
}
