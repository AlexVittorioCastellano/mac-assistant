import Foundation

/// Le voci in cui dividiamo lo spazio occupato.
public enum DiskCategory: String, Sendable, CaseIterable {
    case appleAI          // modelli di Apple Intelligence e Siri
    case systemAssets     // altre risorse scaricate da macOS (voci, font, dizionari…)
    case applications
    case downloads, desktop, documents, pictures, movies, music
    case trash
    case caches           // cache e file temporanei
    case appData          // ~/Library/Application Support
    case iosBackups       // backup di iPhone/iPad
    case otherAIModels    // modelli scaricati da app come Ollama o LM Studio
    case developer        // Xcode, simulatori
    case swap             // memoria virtuale e immagine di stop

    /// Fa parte di quello che Impostazioni chiama "Dati di sistema".
    public var isSystemData: Bool {
        switch self {
        case .appleAI, .systemAssets, .caches, .appData, .iosBackups, .otherAIModels, .developer, .swap: true
        default: false
        }
    }
}

public struct DiskItem: Sendable, Equatable {
    public var category: DiskCategory
    public var bytes: UInt64
    /// Cartella rappresentativa (per l'icona del Finder), se c'è.
    public var path: String?

    public init(category: DiskCategory, bytes: UInt64, path: String? = nil) {
        self.category = category
        self.bytes = bytes
        self.path = path
    }
}

/// Fotografia dello spazio su disco. Solo dati: nessuna logica, nessuna AI.
public struct DiskUsage: Sendable, Equatable {
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    /// Spazio occupato che macOS può liberare da solo (cache, istantanee…).
    public var purgeableBytes: UInt64
    /// macOS stesso (volume di sistema, avvio, ripristino).
    public var macOSBytes: UInt64
    public var items: [DiskItem]
    public var localSnapshotCount: Int

    public init(totalBytes: UInt64, freeBytes: UInt64, purgeableBytes: UInt64, macOSBytes: UInt64,
                items: [DiskItem], localSnapshotCount: Int) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.macOSBytes = macOSBytes
        self.items = items
        self.localSnapshotCount = localSnapshotCount
    }

    public var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }

    /// Quello che non riusciamo ad attribuire (file sparsi, dati di altre app,
    /// cartelle protette che non leggiamo).
    public var otherBytes: UInt64 {
        let known = macOSBytes + items.reduce(0) { $0 + $1.bytes }
        return usedBytes > known ? usedBytes - known : 0
    }

    public func bytes(_ c: DiskCategory) -> UInt64 {
        items.first { $0.category == c }?.bytes ?? 0
    }
}
