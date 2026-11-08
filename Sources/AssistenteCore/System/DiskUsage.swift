import Foundation

public enum DiskCategory: String, Sendable, CaseIterable {
    case appleAI
    case systemAssets
    case applications
    case downloads, desktop, documents, pictures, movies, music
    case trash
    case caches
    case appData
    case iosBackups
    case otherAIModels
    case developer
    case swap

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

    public var path: String?

    public init(category: DiskCategory, bytes: UInt64, path: String? = nil) {
        self.category = category
        self.bytes = bytes
        self.path = path
    }
}

public struct DiskUsage: Sendable, Equatable {
    public var totalBytes: UInt64
    public var freeBytes: UInt64

    public var purgeableBytes: UInt64

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

    public var otherBytes: UInt64 {
        let known = macOSBytes + items.reduce(0) { $0 + $1.bytes }
        return usedBytes > known ? usedBytes - known : 0
    }

    public func bytes(_ c: DiskCategory) -> UInt64 {
        items.first { $0.category == c }?.bytes ?? 0
    }
}
