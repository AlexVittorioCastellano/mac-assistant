public enum KnownProcesses {
    public static var notes: [String: String] {
        let current = L.current.processes
        let fallback = L.packs[L.fallbackCode]?.processes ?? [:]
        return fallback.merging(current) { _, new in new }
    }

    public static func note(for name: String) -> String? {
        let all = notes
        return all[name] ?? all.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
