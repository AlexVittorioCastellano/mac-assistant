import CoreServices
import Foundation

public struct CleanupItem: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        case installer

        case unusedDownload(days: Int)

        case large
    }

    public var id: String { path }
    public var name: String
    public var path: String
    public var bytes: UInt64
    public var reason: Reason

    public var preselected: Bool

    public init(name: String, path: String, bytes: UInt64, reason: Reason, preselected: Bool) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.reason = reason
        self.preselected = preselected
    }

    public var explanation: String {
        switch reason {
        case .installer: L.t("cleanup.reason.installer")
        case .unusedDownload(let days) where days >= 365: L.t("cleanup.reason.year")
        case .unusedDownload(let days): L.t("cleanup.reason.months", days / 30)
        case .large: L.t("cleanup.reason.large")
        }
    }
}

public enum Cleanup {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg"]
    static let unusedDays = 90
    static let largeBytes: UInt64 = 500 * 1_048_576

    public static func candidates(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                                  now: Date = Date()) async -> [CleanupItem] {
        var found: [String: CleanupItem] = [:]
        let downloads = "\(home)/Downloads"

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
            if v?.isPackage == true { enumerator.skipDescendants(); continue }
            if v?.isRegularFile == true, let size = v?.totalFileAllocatedSize, UInt64(size) >= largeBytes {
                result.append((url.path, UInt64(size)))
            }
        }
        return result
    }

    public struct TrashResult: Sendable {
        public var moved: [(original: String, inTrash: String)]
        public var bytes: UInt64
        public var refused: [String]
    }

    public static func isSafeToTouch(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard p.hasPrefix(home + "/"), p != home else { return false }
        let relative = String(p.dropFirst(home.count + 1))
        return !relative.hasPrefix("Library") && !relative.hasPrefix(".")
    }

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

    public static func undo(_ result: TrashResult) -> Int {
        var restored = 0
        for (original, inTrash) in result.moved where !inTrash.isEmpty {
            if (try? FileManager.default.moveItem(atPath: inTrash, toPath: original)) != nil { restored += 1 }
        }
        return restored
    }
}
