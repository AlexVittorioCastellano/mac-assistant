import Foundation

public struct MacStatus: Sendable, Equatable {
    public var fileVaultOn: Bool?
    public var firewallOn: Bool?
    public var gatekeeperOn: Bool?
    public var sipOn: Bool?
    public var backup: BackupStatus
    public var automaticUpdatesOn: Bool?

    public var pendingUpdates: Int?

    public var battery: BatteryHealth?

    public init(fileVaultOn: Bool? = nil, firewallOn: Bool? = nil, gatekeeperOn: Bool? = nil, sipOn: Bool? = nil,
                backup: BackupStatus = .unknown, automaticUpdatesOn: Bool? = nil, pendingUpdates: Int? = nil,
                battery: BatteryHealth? = nil) {
        self.fileVaultOn = fileVaultOn
        self.firewallOn = firewallOn
        self.gatekeeperOn = gatekeeperOn
        self.sipOn = sipOn
        self.backup = backup
        self.automaticUpdatesOn = automaticUpdatesOn
        self.pendingUpdates = pendingUpdates
        self.battery = battery
    }
}

public enum BackupStatus: Sendable, Equatable {
    case notConfigured

    case configured(lastBackup: Date?)
    case unknown
}

public struct BatteryHealth: Sendable, Equatable {
    public var healthPercent: Int
    public var cycleCount: Int

    public init(healthPercent: Int, cycleCount: Int) {
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
    }
}

public struct MacStatusMonitor: Sendable {
    public init() {}

    public func status() async -> MacStatus {
        async let fileVault = Self.flag(Shell.run("/usr/bin/fdesetup", ["status"]), on: "FileVault is On", off: "FileVault is Off")
        async let firewall = Self.flag(Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]),
                                       on: "enabled", off: "disabled")
        async let gatekeeper = Self.flag(Shell.run("/usr/sbin/spctl", ["--status"]),
                                         on: "assessments enabled", off: "assessments disabled")
        async let sip = Self.flag(Shell.run("/usr/bin/csrutil", ["status"]), on: "status: enabled", off: "status: disabled")
        async let destinations = Shell.run("/usr/bin/tmutil", ["destinationinfo"])
        async let battery = Shell.run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"])

        let updates = Self.softwareUpdatePrefs()
        return MacStatus(
            fileVaultOn: await fileVault,
            firewallOn: await firewall,
            gatekeeperOn: await gatekeeper,
            sipOn: await sip,
            backup: Self.backupStatus(destinationInfo: await destinations),
            automaticUpdatesOn: updates.automatic,
            pendingUpdates: updates.pending,
            battery: Self.parseBattery(await battery))
    }

    static func flag(_ output: String?, on: String, off: String) async -> Bool? {
        guard let output else { return nil }
        if output.localizedCaseInsensitiveContains(off) { return false }
        if output.localizedCaseInsensitiveContains(on) { return true }
        return nil
    }

    static func backupStatus(destinationInfo: String?) -> BackupStatus {
        guard let info = destinationInfo else { return .unknown }
        if info.contains("No destinations configured") { return .notConfigured }
        return .configured(lastBackup: lastBackupDate())
    }

    static func lastBackupDate() -> Date? {
        let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.TimeMachine.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let destinations = plist["Destinations"] as? [[String: Any]] else { return nil }
        return destinations.flatMap { $0["SnapshotDates"] as? [Date] ?? [] }.max()
    }

    static func softwareUpdatePrefs() -> (automatic: Bool?, pending: Int?) {
        let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.SoftwareUpdate.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return (nil, nil) }
        let automatic = (plist["AutomaticallyInstallMacOSUpdates"] as? Bool)
            ?? (plist["AutomaticDownload"] as? Bool)
        let pending = (plist["RecommendedUpdates"] as? [Any])?.count
            ?? (plist["LastRecommendedUpdatesAvailable"] as? Int)
        return (automatic, pending)
    }

    static func parseBattery(_ output: String?) -> BatteryHealth? {
        guard let data = output?.data(using: .utf8),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]],
              let b = list.first else { return nil }

        let batteryData = b["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { (b[key] as? Int) ?? (batteryData[key] as? Int) }
        let design = int("DesignCapacity") ?? 0
        let raw = int("AppleRawMaxCapacity") ?? int("FullChargeCapacity") ?? 0
        guard design > 0, raw > 0 else { return nil }
        let health = min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        return BatteryHealth(healthPercent: health, cycleCount: int("CycleCount") ?? 0)
    }
}
