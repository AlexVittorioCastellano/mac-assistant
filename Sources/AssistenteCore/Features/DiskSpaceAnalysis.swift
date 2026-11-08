import Foundation

public enum DiskSpaceAnalysis {
    struct Entry {
        var id: String
        var label: String
        var bytes: UInt64
        var iconPath: String?
        var symbol: String
        var advice: String?
    }

    static func label(_ c: DiskCategory) -> String {
        L.t("disk.label." + c.rawValue)
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

    static func advice(_ c: DiskCategory) -> String? {
        switch c {
        case .appleAI, .downloads, .trash, .applications, .pictures, .caches, .iosBackups, .otherAIModels, .developer, .swap:
            L.t("disk.advice." + c.rawValue)
        case .movies, .music, .documents, .desktop:
            L.t("disk.advice.files")
        case .systemAssets, .appData:
            nil
        }
    }

    static func entries(_ u: DiskUsage) -> [Entry] {
        var list = u.items.map {
            Entry(id: $0.category.rawValue, label: label($0.category), bytes: $0.bytes,
                  iconPath: $0.path, symbol: symbol($0.category), advice: advice($0.category))
        }
        list.append(Entry(id: "macos", label: L.t("disk.label.macos"), bytes: u.macOSBytes, symbol: "apple.logo"))

        list.append(Entry(id: "other", label: L.t("disk.label.other"),
                          bytes: u.otherBytes, symbol: "ellipsis.circle"))
        return list.sorted { $0.bytes > $1.bytes }
    }

    public static func systemDataBytes(_ u: DiskUsage) -> UInt64 {
        u.items.filter { $0.category.isSystemData }.reduce(0) { $0 + $1.bytes } + u.otherBytes
    }

    static func level(_ u: DiskUsage) -> Finding.Severity {
        let gb: UInt64 = 1_073_741_824
        let freeRatio = u.totalBytes > 0 ? Double(u.freeBytes) / Double(u.totalBytes) : 1
        if freeRatio < 0.1 || u.freeBytes < 10 * gb { return .critical }
        return freeRatio < 0.2 ? .warning : .ok
    }

    public static let coloredEntries = 5

    static func split(_ u: DiskUsage) -> (top: [Entry], rest: [Entry]) {
        let all = entries(u).filter { $0.bytes > 0 }
        return (Array(all.prefix(coloredEntries)), Array(all.dropFirst(coloredEntries)))
    }

    public static func chart(for u: DiskUsage) -> SegmentedChart {
        let (top, rest) = split(u)
        var segments = top.enumerated().map { i, e in
            SegmentedChart.Segment(id: e.id, label: e.label, bytes: e.bytes, swatch: .series(i))
        }
        let restBytes = rest.reduce(0) { $0 + $1.bytes }
        if restBytes > 0 {
            segments.append(.init(id: "rest", label: L.t("disk.label.rest"), bytes: restBytes, swatch: .rest))
        }
        return SegmentedChart(totalBytes: segments.reduce(0) { $0 + $1.bytes }, segments: segments,
                              capacityBytes: u.totalBytes, level: level(u))
    }

    public static func findings(for u: DiskUsage) -> [Finding] {
        var result: [Finding] = []
        let gb: UInt64 = 1_073_741_824

        let summary = L.t("disk.free", Fmt.size(u.freeBytes), Fmt.size(u.totalBytes))
        let severity = level(u)

        let plenty = severity == .ok
        result.append(.init(id: "free", severity: severity, title: summary,
                            advice: plenty ? L.t("disk.free.plenty") : L.t("disk.free.low"),
                            symbol: "internaldrive"))

        if u.purgeableBytes >= gb {
            result.append(.init(id: "purgeable", severity: .info,
                                title: L.t("disk.purgeable", Fmt.size(u.purgeableBytes)),
                                symbol: "arrow.3.trianglepath"))
        }

        let (top, rest) = split(u)
        for (i, e) in top.enumerated() {
            result.append(.init(id: e.id, severity: .info, title: L.t("disk.row", e.label, Fmt.size(e.bytes)),
                                advice: plenty ? nil : e.advice, iconPath: e.iconPath, symbol: e.symbol,
                                swatch: .series(i)))
        }
        let restBytes = rest.reduce(0) { $0 + $1.bytes }
        if restBytes > 0 {
            let names = rest.filter { $0.bytes >= gb }.prefix(3).map(\.label)
            let detail = names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
            var row = Finding(id: "rest", severity: .info, title: L.t("disk.rest", detail, Fmt.size(restBytes)),
                              symbol: "square.grid.2x2", swatch: .rest)

            if !plenty {
                row.moreAdvice = rest.filter { $0.bytes >= gb }.compactMap(\.advice)
            }
            result.append(row)
        }

        let systemData = systemDataBytes(u)
        if systemData >= gb {
            let biggest = u.items.filter { $0.category.isSystemData }.max { $0.bytes < $1.bytes }
            var title = L.t("disk.systemdata", Fmt.size(systemData))
            if let biggest, biggest.bytes >= gb {
                title += L.t("disk.systemdata.biggest", label(biggest.category))
            }
            result.append(.init(id: "systemdata", severity: .info, title: title, symbol: "questionmark.folder"))
        }

        if u.localSnapshotCount > 0 {
            result.append(.init(id: "snapshots", severity: .info,
                                title: L.t("disk.snapshots", u.localSnapshotCount),
                                advice: L.t("disk.snapshots.advice"),
                                symbol: "clock.arrow.circlepath"))
        }
        return result
    }

    public static func request(question: String, usage u: DiskUsage) -> AIRequest {
        let gb: UInt64 = 1_073_741_824
        let list = entries(u).filter { $0.bytes >= gb }.prefix(8)
            .map { "- \($0.label): \(Fmt.size($0.bytes))" }.joined(separator: "\n")
        let state = level(u) == .ok ? L.t("disk.prompt.plenty") : L.t("disk.prompt.low")
        let prompt = L.t("disk.prompt", question, Fmt.size(u.freeBytes), Fmt.size(u.totalBytes), state, list,
                         Fmt.size(systemDataBytes(u)))
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }
}
