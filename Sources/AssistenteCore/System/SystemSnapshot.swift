import Foundation

/// Una "fotografia" dello stato del Mac in un dato momento.
/// Sono solo dati: nessuna logica, nessuna AI.
public struct SystemSnapshot: Sendable, Equatable {
    /// Uso del processore di tutto il Mac, da 0 a 100.
    public var cpuUsagePercent: Double
    public var coreCount: Int
    public var memory: MemoryInfo
    public var thermal: ThermalLevel
    /// Secondi dall'ultima accensione/riavvio.
    public var uptime: TimeInterval
    /// Tutti i programmi in esecuzione, raggruppati per nome.
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
    /// Come "Memoria utilizzata" in Monitoraggio Attività (app + wired + compressa).
    public var usedBytes: UInt64
    /// File in cache: memoria che macOS libera da solo quando serve.
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

/// Un singolo processo, così come lo riporta `ps`.
public struct ProcessSample: Sendable, Equatable {
    public var pid: Int32
    /// Percentuale di UN core (può superare 100 sui Mac multi-core).
    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var user: String
    public var name: String

    public init(pid: Int32, cpuPercent: Double, residentBytes: UInt64, user: String, name: String) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.user = user
        self.name = name
    }
}

/// Processi con lo stesso nome "logico" sommati insieme
/// (es. tutti i "Google Chrome Helper" contano come "Google Chrome").
public struct ProcessGroup: Sendable, Equatable {
    public var name: String
    public var instanceCount: Int
    public var cpuPercent: Double
    public var residentBytes: UInt64
    /// Processo di sistema (utente root o di servizio) e non un'app dell'utente.
    public var isSystem: Bool
    public var pids: [Int32]

    public init(name: String, instanceCount: Int, cpuPercent: Double,
                residentBytes: UInt64, isSystem: Bool, pids: [Int32]) {
        self.name = name
        self.instanceCount = instanceCount
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.isSystem = isSystem
        self.pids = pids
    }
}
