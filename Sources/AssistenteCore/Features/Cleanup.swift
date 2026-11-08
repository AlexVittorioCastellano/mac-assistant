import CoreServices
import Foundation

/// Un file che si potrebbe togliere, con il motivo.
public struct CleanupItem: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        /// Installer (.dmg, .pkg) nei Download: dopo l'installazione non serve più.
        case installer
        /// Nei Download e non aperto da molto tempo.
        case unusedDownload(days: Int)
        /// File molto grande.
        case large
    }

    public var id: String { path }
    public var name: String
    public var path: String
    public var bytes: UInt64
    public var reason: Reason
    /// Proposto già spuntato (solo gli installer: quasi sempre inutili).
    public var preselected: Bool

    public var explanation: String {
        switch reason {
        case .installer: "Installer già scaricato: dopo l'installazione non serve più"
        case .unusedDownload(let days) where days >= 365: "Nei Download, non lo apri da più di un anno"
        case .unusedDownload(let days): "Nei Download, non lo apri da \(days / 30) mesi"
        case .large: "File molto grande"
        }
    }
}

/// Funzione "Pulizia guidata".
///
/// L'app PROPONE dei file; l'utente sceglie cosa togliere e conferma; i file
/// vanno nel Cestino (si possono recuperare) e l'ultima pulizia si può
/// annullare. Questo è l'UNICO punto dell'app che sposta file.
public enum Cleanup {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg"]
    static let unusedDays = 90
    static let largeBytes: UInt64 = 500 * 1_048_576

    // MARK: Ricerca (sola lettura)

    public static func candidates(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                                  now: Date = Date()) async -> [CleanupItem] {
        var found: [String: CleanupItem] = [:]
        let downloads = "\(home)/Downloads"

        // 1. Download: installer e file non usati da tempo.
        for path in children(of: downloads) {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let bytes = await size(of: path)
            let days = daysSinceLastUse(path, now: now)
            if installerExtensions.contains(ext), days >= 2 {
                found[path] = item(path, bytes, .installer, preselected: true)
            } else if days >= unusedDays, bytes >= 1_048_576 {
                found[path] = item(path, bytes, .unusedDownload(days: days), preselected: false)
            }
        }

        // 2. File molto grandi nelle cartelle dell'utente (non in Libreria).
        for folder in ["Desktop", "Documents", "Movies", "Downloads"] {
            for (path, bytes) in largeFiles(in: "\(home)/\(folder)") where found[path] == nil {
                found[path] = item(path, bytes, .large, preselected: false)
            }
        }
        return found.values.sorted { $0.bytes > $1.bytes }.prefix(30).map { $0 }
    }

    static func item(_ path: String, _ bytes: UInt64, _ reason: CleanupItem.Reason, preselected: Bool) -> CleanupItem {
        CleanupItem(name: URL(fileURLWithPath: path).lastPathComponent, path: path, bytes: bytes,
                    reason: reason, preselected: preselected)
    }

    static func children(of folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .map { "\(folder)/\($0)" }
    }

    static func size(of path: String) async -> UInt64 {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue { return await DiskMonitor.size(of: [path]) ?? 0 }
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return UInt64(values?.totalFileAllocatedSize ?? 0)
    }

    /// Giorni dall'ultimo utilizzo (data "Ultima apertura" del Finder; se manca,
    /// la data in cui il file è arrivato nella cartella).
    static func daysSinceLastUse(_ path: String, now: Date) -> Int {
        var date: Date?
        if let item = MDItemCreate(nil, path as CFString) {
            date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
                ?? MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        }
        if date == nil {
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            date = values?.addedToDirectoryDate ?? values?.creationDate
        }
        guard let date else { return 0 }
        return max(0, Int(now.timeIntervalSince(date) / 86_400))
    }

    static func largeFiles(in folder: String) -> [(String, UInt64)] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: folder),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey, .isPackageKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var result: [(String, UInt64)] = []
        for case let url as URL in enumerator {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey, .isPackageKey])
            if v?.isPackage == true { enumerator.skipDescendants(); continue }  // app e librerie di Foto: non entrarci
            if v?.isRegularFile == true, let size = v?.totalFileAllocatedSize, UInt64(size) >= largeBytes {
                result.append((url.path, UInt64(size)))
            }
        }
        return result
    }

    // MARK: Azione (solo dopo la conferma dell'utente)

    public struct TrashResult: Sendable {
        /// Percorso originale → percorso nel Cestino (per poter annullare).
        public var moved: [(original: String, inTrash: String)]
        public var bytes: UInt64
        public var refused: [String]
    }

    /// `true` se l'app può toccare questo file: solo dentro la cartella
    /// dell'utente, mai in Libreria né in file di sistema.
    public static func isSafeToTouch(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard p.hasPrefix(home + "/"), p != home else { return false }
        let relative = String(p.dropFirst(home.count + 1))
        return !relative.hasPrefix("Library") && !relative.hasPrefix(".")
    }

    /// Sposta i file nel Cestino. Rifiuta tutto ciò che non è sicuro.
    public static func moveToTrash(_ items: [CleanupItem],
                                   home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> TrashResult {
        var result = TrashResult(moved: [], bytes: 0, refused: [])
        for item in items {
            guard isSafeToTouch(item.path, home: home), FileManager.default.fileExists(atPath: item.path) else {
                result.refused.append(item.name)
                continue
            }
            var trashURL: NSURL?
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &trashURL)
                result.moved.append((item.path, trashURL?.path ?? ""))
                result.bytes += item.bytes
            } catch {
                result.refused.append(item.name)
            }
        }
        return result
    }

    /// Annulla: riporta i file dal Cestino al loro posto.
    public static func undo(_ result: TrashResult) -> Int {
        var restored = 0
        for (original, inTrash) in result.moved where !inTrash.isEmpty {
            if (try? FileManager.default.moveItem(atPath: inTrash, toPath: original)) != nil { restored += 1 }
        }
        return restored
    }
}
