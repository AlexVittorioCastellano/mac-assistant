import Foundation

public struct DiskMonitor: Sendable {
    public init() {}

    public func usage() async -> DiskUsage {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let assets = "/System/Library/AssetsV2"

        let assetFolders = (try? FileManager.default.contentsOfDirectory(atPath: assets)) ?? []
        let aiFolders = assetFolders.filter { $0.hasPrefix("com_apple_MobileAsset_UAF_") }.map { "\(assets)/\($0)" }

        let plan: [(DiskCategory, [String], String?)] = [
            (.appleAI, aiFolders, nil),
            (.systemAssets, [assets], nil),
            (.applications, ["/Applications"], "/Applications"),
            (.downloads, ["\(home)/Downloads"], "\(home)/Downloads"),
            (.desktop, ["\(home)/Desktop"], "\(home)/Desktop"),
            (.documents, ["\(home)/Documents"], "\(home)/Documents"),
            (.pictures, ["\(home)/Pictures"], "\(home)/Pictures"),
            (.movies, ["\(home)/Movies"], "\(home)/Movies"),
            (.music, ["\(home)/Music"], "\(home)/Music"),
            (.trash, ["\(home)/.Trash"], nil),
            (.caches, ["\(home)/Library/Caches", "/Library/Caches", "/private/var/folders"], nil),
            (.appData, ["\(home)/Library/Application Support"], nil),
            (.iosBackups, ["\(home)/Library/Application Support/MobileSync/Backup"], nil),
            (.otherAIModels, ["\(home)/.ollama", "\(home)/.cache/huggingface", "\(home)/.lmstudio", "\(home)/.cache/lm-studio"], nil),
            (.developer, ["\(home)/Library/Developer"], nil),
            (.swap, ["/private/var/vm"], nil),
        ]

        var sizes: [DiskCategory: UInt64] = [:]
        await withTaskGroup(of: (DiskCategory, UInt64?).self) { group in
            for (category, paths, _) in plan {
                group.addTask { (category, await Self.size(of: paths)) }
            }
            for await (category, bytes) in group {
                if let bytes { sizes[category] = bytes }
            }
        }

        if let all = sizes[.systemAssets] { sizes[.systemAssets] = all - min(all, sizes[.appleAI] ?? 0) }
        if let all = sizes[.appData] { sizes[.appData] = all - min(all, sizes[.iosBackups] ?? 0) }

        let items = plan.compactMap { category, _, icon in
            sizes[category].map { DiskItem(category: category, bytes: $0, path: icon) }
        }

        let volume = Self.volumeCapacity()
        let container = await Self.apfsContainer()
        return DiskUsage(
            totalBytes: container?.total ?? volume.total,
            freeBytes: container?.free ?? volume.free,
            purgeableBytes: volume.purgeable,
            macOSBytes: container?.macOS ?? 0,
            items: items,
            localSnapshotCount: await Self.localSnapshotCount())
    }

    public static func size(of paths: [String]) async -> UInt64? {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return 0 }
        guard let output = await Shell.run("/usr/bin/du", ["-sk"] + existing) else { return nil }
        let kilobytes = output.split(separator: "\n").compactMap { line in
            line.split(separator: "\t").first.flatMap { UInt64($0) }
        }
        return kilobytes.isEmpty ? nil : kilobytes.reduce(0, +) * 1024
    }

    public static func volumeCapacity() -> (total: UInt64, free: UInt64, purgeable: UInt64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys)
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        let free = UInt64(values?.volumeAvailableCapacity ?? 0)
        let important = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
        return (total, free, important > free ? important - free : 0)
    }

    static func apfsContainer() async -> (total: UInt64, free: UInt64, macOS: UInt64)? {
        guard let output = await Shell.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"]),
              let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return nil }
        return parseContainers(containers)
    }

    static func parseContainers(_ containers: [[String: Any]]) -> (total: UInt64, free: UInt64, macOS: UInt64)? {
        func roles(_ v: [String: Any]) -> [String] { v["Roles"] as? [String] ?? [] }

        guard let boot = containers.first(where: { c in
            let all = (c["Volumes"] as? [[String: Any]] ?? []).flatMap(roles)
            return all.contains("System") && all.contains("Data")
        }) else { return nil }
        let volumes = boot["Volumes"] as? [[String: Any]] ?? []
        let macOSRoles: Set<String> = ["System", "Preboot", "Recovery", "Update"]
        let macOS = volumes
            .filter { !macOSRoles.isDisjoint(with: roles($0)) }
            .reduce(UInt64(0)) { $0 + ((($1["CapacityInUse"] as? NSNumber)?.uint64Value) ?? 0) }
        let total = (boot["CapacityCeiling"] as? NSNumber)?.uint64Value ?? 0
        let free = (boot["CapacityFree"] as? NSNumber)?.uint64Value ?? 0
        return (total, free, macOS)
    }

    static func localSnapshotCount() async -> Int {
        guard let output = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return 0 }
        return output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
    }
}
