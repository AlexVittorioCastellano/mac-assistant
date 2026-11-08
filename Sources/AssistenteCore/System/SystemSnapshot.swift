import Foundation

public struct SystemSnapshot: Sendable, Equatable {
    public var cpuUsagePercent: Double
    public var coreCount: Int
    public var memory: MemoryInfo
    public var thermal: ThermalLevel

    public var uptime: TimeInterval

    public var processes: [ProcessGroup]

    public init(cpuUsagePercent: Double, coreCount: Int, memory: MemoryInfo,
                thermal: ThermalLevel, uptime: TimeInterval, processes: [ProcessGroup]) {
        self.cpuUsagePercent = cpuUsagePercent
        self.coreCount = coreCount
        self.memory = memory
        self.thermal = thermal
        self.uptime = uptime
        self.processes = processes
    }

    public func topByCPU(_ n: Int) -> [ProcessGroup] {
        Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(n))
    }

    public func topByMemory(_ n: Int) -> [ProcessGroup] {
        Array(processes.sorted { $0.residentBytes > $1.residentBytes }.prefix(n))
    }
}

public struct MemoryInfo: Sendable, Equatable {
    public var totalBytes: UInt64

    public var usedBytes: UInt64

    public var cachedBytes: UInt64
    public var compressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: MemoryPressure

    public init(totalBytes: UInt64, usedBytes: UInt64, cachedBytes: UInt64,
                compressedBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.cachedBytes = cachedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }
}

public enum MemoryPressure: String, Sendable, Equatable {
    case normal, warning, critical
}

public enum ThermalLevel: String, Sendable, Equatable {
    case nominal, fair, serious, critical
}

public struct ProcessSample: Sendable, Equatable {
    public var pid: Int32

    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var user: String
    public var name: String

    public var path: String?

    public init(pid: Int32, cpuPercent: Double, residentBytes: UInt64, user: String, name: String, path: String? = nil) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.user = user
        self.name = name
        self.path = path
    }
}

public struct ProcessGroup: Sendable, Equatable {
    public var name: String
    public var instanceCount: Int
    public var cpuPercent: Double
    public var residentBytes: UInt64

    public var isSystem: Bool
    public var pids: [Int32]
    public var path: String?
    public var kind: ProcessKind

    public init(name: String, instanceCount: Int, cpuPercent: Double,
                residentBytes: UInt64, isSystem: Bool, pids: [Int32],
                path: String? = nil, kind: ProcessKind? = nil) {
        self.name = name
        self.instanceCount = instanceCount
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.isSystem = isSystem
        self.pids = pids
        self.path = path
        self.kind = kind ?? (isSystem ? .macOS : .unknown)
    }
}
