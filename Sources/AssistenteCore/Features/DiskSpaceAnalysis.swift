import Foundation

/// Funzione 3: "Dove è finito lo spazio?"
///
/// Il codice misura le cartelle e decide cosa mostrare e quali consigli dare
/// (tutti sicuri: l'app non cancella mai nulla). L'AI spiega il quadro in
/// poche frasi, compreso cosa sono i "Dati di sistema".
public enum DiskSpaceAnalysis {

    /// Una voce mostrata all'utente (categoria misurata, macOS o "altro").
    struct Entry {
        var id: String
        var label: String
        var bytes: UInt64
        var iconPath: String?
        var symbol: String
        var advice: String?
    }

    static func label(_ c: DiskCategory) -> String {
        switch c {
        case .appleAI: "Modelli di Apple Intelligence e Siri"
        case .systemAssets: "Risorse scaricate da macOS (voci, font, dizionari…)"
        case .applications: "Applicazioni"
        case .downloads: "Download"
        case .desktop: "Scrivania"
        case .documents: "Documenti"
        case .pictures: "Immagini e libreria di Foto"
        case .movies: "Filmati"
        case .music: "Musica"
        case .trash: "Cestino"
        case .caches: "Cache e file temporanei"
        case .appData: "Dati delle app"
        case .iosBackups: "Backup di iPhone e iPad"
        case .otherAIModels: "Modelli AI di altre app (es. Ollama, LM Studio)"
        case .developer: "Strumenti per sviluppatori (Xcode, simulatori)"
        case .swap: "Memoria virtuale e stop"
        }
    }

    static func symbol(_ c: DiskCategory) -> String {
        switch c {
        case .appleAI: "sparkles"
        case .systemAssets: "shippingbox"
        case .trash: "trash"
        case .caches: "archivebox"
        case .appData: "square.stack.3d.up"
        case .iosBackups: "iphone"
        case .otherAIModels: "cpu"
        case .developer: "hammer"
        case .swap: "memorychip"
        default: "folder"
        }
    }

    /// Consigli: solo azioni sicure che fa l'utente, mai cancellazioni automatiche.
    static func advice(_ c: DiskCategory) -> String? {
        switch c {
        case .appleAI:
            "Se non usi Apple Intelligence, puoi disattivarla in Impostazioni di Sistema → Apple Intelligence e Siri: macOS potrà liberare parte di questo spazio (questa app però la usa per le spiegazioni)."
        case .downloads:
            "Guarda nella cartella Download: spesso ci sono installer e archivi che non servono più."
        case .trash:
            "Svuota il Cestino: clic destro sull'icona del Cestino nel Dock → Svuota il Cestino."
        case .applications:
            "Elimina le app che non usi più: trascinale dalla cartella Applicazioni al Cestino."
        case .pictures:
            "Se usi Foto di iCloud, puoi attivare «Ottimizza spazio Mac» in Foto → Impostazioni → iCloud."
        case .movies, .music, .documents, .desktop:
            "I file grandi che usi poco puoi spostarli su un disco esterno o su iCloud Drive."
        case .caches:
            "Le cache non vanno cancellate a mano: macOS le libera da solo quando lo spazio scarseggia."
        case .iosBackups:
            "Puoi eliminare i backup vecchi dal Finder: seleziona il dispositivo → Gestisci backup."
        case .otherAIModels:
            "Sono modelli scaricati da app come Ollama o LM Studio: elimina quelli che non usi dall'app stessa."
        case .developer:
            "Se usi Xcode: simulatori e file di build vecchi si possono eliminare da Xcode → Impostazioni → Componenti."
        case .swap:
            "La memoria virtuale si riduce da sola riavviando il Mac."
        case .systemAssets, .appData:
            nil
        }
    }

    /// Tutte le voci, dalla più grande, compresi macOS e "altro".
    static func entries(_ u: DiskUsage) -> [Entry] {
        var list = u.items.map {
            Entry(id: $0.category.rawValue, label: label($0.category), bytes: $0.bytes,
                  iconPath: $0.path, symbol: symbol($0.category), advice: advice($0.category))
        }
        list.append(Entry(id: "macos", label: "macOS", bytes: u.macOSBytes, symbol: "apple.logo"))
        // Non chiamarlo "Altro": si confonderebbe con "Il resto" del grafico.
        list.append(Entry(id: "other", label: "Dati di altre app e file sparsi",
                          bytes: u.otherBytes, symbol: "ellipsis.circle"))
        return list.sorted { $0.bytes > $1.bytes }
    }

    /// Circa quello che Impostazioni chiama "Dati di sistema".
    public static func systemDataBytes(_ u: DiskUsage) -> UInt64 {
        u.items.filter { $0.category.isSystemData }.reduce(0) { $0 + $1.bytes } + u.otherBytes
    }

    // MARK: Cosa mostrare

    /// Quanto è grave: critico sotto il 10% (o 10 GB) liberi, attenzione sotto il 20%.
    static func level(_ u: DiskUsage) -> Finding.Severity {
        let gb: UInt64 = 1_073_741_824
        let freeRatio = u.totalBytes > 0 ? Double(u.freeBytes) / Double(u.totalBytes) : 1
        if freeRatio < 0.1 || u.freeBytes < 10 * gb { return .critical }
        return freeRatio < 0.2 ? .warning : .ok
    }

    /// Quante voci hanno un colore proprio nel grafico; le altre vanno in "Il resto".
    /// Massimo 5: oltre, i colori diventano difficili da distinguere.
    public static let coloredEntries = 5

    /// Le voci colorate e quelle raggruppate in "Il resto".
    static func split(_ u: DiskUsage) -> (top: [Entry], rest: [Entry]) {
        let all = entries(u).filter { $0.bytes > 0 }
        return (Array(all.prefix(coloredEntries)), Array(all.dropFirst(coloredEntries)))
    }

    /// Barra segmentata dello spazio USATO (le voci più grandi e il resto),
    /// più la capacità del disco per l'indicatore "usati X su Y".
    /// Lo spazio libero non è un blocco: su un disco quasi vuoto renderebbe
    /// le voci strisce illeggibili.
    public static func chart(for u: DiskUsage) -> SegmentedChart {
        let (top, rest) = split(u)
        var segments = top.enumerated().map { i, e in
            SegmentedChart.Segment(id: e.id, label: e.label, bytes: e.bytes, swatch: .series(i))
        }
        let restBytes = rest.reduce(0) { $0 + $1.bytes }
        if restBytes > 0 {
            segments.append(.init(id: "rest", label: "Il resto", bytes: restBytes, swatch: .rest))
        }
        return SegmentedChart(totalBytes: segments.reduce(0) { $0 + $1.bytes }, segments: segments,
                              capacityBytes: u.totalBytes, level: level(u))
    }

    public static func findings(for u: DiskUsage) -> [Finding] {
        var result: [Finding] = []
        let gb: UInt64 = 1_073_741_824

        let summary = "Spazio libero: \(Fmt.size(u.freeBytes)) su \(Fmt.size(u.totalBytes))"
        let severity = level(u)
        // Con tanto spazio libero, i consigli di pulizia sarebbero inutili:
        // lo diciamo chiaramente e mostriamo solo le informazioni.
        let plenty = severity == .ok
        result.append(.init(id: "free", severity: severity, title: summary,
                            advice: plenty ? "Hai ancora molto spazio libero: non serve liberarne adesso."
                                : "Premi «Pulizia» per scegliere i file da togliere (vanno nel Cestino, recuperabili).",
                            symbol: "internaldrive"))

        if u.purgeableBytes >= gb {
            result.append(.init(id: "purgeable", severity: .info,
                                title: "Altri \(Fmt.size(u.purgeableBytes)) macOS li libera da solo quando servono",
                                symbol: "arrow.3.trianglepath"))
        }

        // Le righe hanno lo stesso ordine e lo stesso colore dei blocchi della barra.
        let (top, rest) = split(u)
        for (i, e) in top.enumerated() {
            result.append(.init(id: e.id, severity: .info, title: "\(e.label): \(Fmt.size(e.bytes))",
                                advice: plenty ? nil : e.advice, iconPath: e.iconPath, symbol: e.symbol,
                                swatch: .series(i)))
        }
        let restBytes = rest.reduce(0) { $0 + $1.bytes }
        if restBytes > 0 {
            // Nomino le voci raggruppate più grandi, così "il resto" non è un mistero.
            let names = rest.filter { $0.bytes >= gb }.prefix(3).map(\.label)
            let detail = names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
            var row = Finding(id: "rest", severity: .info, title: "Il resto\(detail): \(Fmt.size(restBytes))",
                              symbol: "square.grid.2x2", swatch: .rest)
            // Consigli delle voci raggruppate, se lo spazio scarseggia (es. un Cestino pieno).
            if !plenty {
                row.moreAdvice = rest.filter { $0.bytes >= gb }.compactMap(\.advice)
            }
            result.append(row)
        }

        let systemData = systemDataBytes(u)
        if systemData >= gb {
            let biggest = u.items.filter { $0.category.isSystemData }.max { $0.bytes < $1.bytes }
            var title = "In Impostazioni, «Dati di sistema» è circa \(Fmt.size(systemData))"
            if let biggest, biggest.bytes >= gb {
                title += ". La voce più grande: «\(label(biggest.category))»"
            }
            result.append(.init(id: "systemdata", severity: .info, title: title, symbol: "questionmark.folder"))
        }

        if u.localSnapshotCount > 0 {
            result.append(.init(id: "snapshots", severity: .info,
                                title: "\(u.localSnapshotCount) istantanee locali di Time Machine",
                                advice: "Le istantanee le elimina macOS da solo dopo circa 24 ore o quando serve spazio.",
                                symbol: "clock.arrow.circlepath"))
        }
        return result
    }

    // MARK: Richiesta all'AI

    public static func request(question: String, usage u: DiskUsage) -> AIRequest {
        let gb: UInt64 = 1_073_741_824
        let list = entries(u).filter { $0.bytes >= gb }.prefix(8)
            .map { "- \($0.label): \(Fmt.size($0.bytes))" }.joined(separator: "\n")
        let prompt = """
        Domanda dell'utente: \(question)

        Disco: \(Fmt.size(u.freeBytes)) liberi su \(Fmt.size(u.totalBytes)) \
        (\(level(u) == .ok ? "lo spazio libero è abbondante" : "lo spazio libero sta finendo")).
        Voci più grandi (misurate dall'app):
        \(list)

        Informazioni sicure:
        - In Impostazioni di Sistema → Generali → Spazio, «Dati di sistema» raccoglie tutto ciò che non è \
        nelle altre categorie: modelli di Apple Intelligence, cache, memoria virtuale, istantanee \
        di Time Machine, dati delle app. In questo Mac sono circa \(Fmt.size(systemDataBytes(u))).
        - I modelli di Apple Intelligence servono per le funzioni AI che lavorano sul Mac.
        - Le cache e le istantanee macOS le libera da solo quando serve spazio.

        Spiega in 2 o 3 frasi semplici dove è finito lo spazio, partendo dalle voci più grandi.
        Se i «Dati di sistema» sono tanti, spiega cosa sono.
        Non dare consigli e non fare elenchi: i consigli li mostra già l'app.
        """
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }
}
