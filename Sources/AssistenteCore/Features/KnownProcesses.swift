/// Brevi spiegazioni di processi comuni di macOS, nella lingua corrente
/// (pacchetti lingua, sezione "processes").
///
/// Il modello on-device è piccolo e spesso non conosce questi nomi: queste
/// note gli danno una base corretta. Contributi benvenuti! Regole:
/// - una frase breve, semplice, senza gergo;
/// - solo informazioni di cui si è sicuri;
/// - le stesse chiavi (nomi dei processi) in tutte le lingue.
public enum KnownProcesses {
    public static var notes: [String: String] {
        let current = L.current.processes
        let fallback = L.packs[L.fallbackCode]?.processes ?? [:]
        return fallback.merging(current) { _, new in new }
    }

    /// Cerca la nota ignorando maiuscole/minuscole.
    public static func note(for name: String) -> String? {
        let all = notes
        return all[name] ?? all.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
