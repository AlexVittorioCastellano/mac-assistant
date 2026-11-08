import Foundation
import Darwin

/// Raccoglie i dati di sistema (CPU, memoria, temperatura, processi).
/// Solo lettura. Nessun dato viene salvato o inviato.
public struct SystemMonitor: Sendable {
    public init() {}

    /// Misura lo stato attuale. Per la CPU servono due letture a distanza
    /// di `sampleInterval`: l'uso è la differenza tra le due.
    public func snapshot(sampleInterval: Duration = .milliseconds(500)) async throws -> SystemSnapshot {
        let before = Self.cpuTicks()
        try await Task.sleep(for: sampleInterval)
        let after = Self.cpuTicks()

        let info = ProcessInfo.processInfo
        return SystemSnapshot(
            cpuUsagePercent: Self.cpuUsage(from: before, to: after),
            coreCount: info.activeProcessorCount,
            memory: Self.memory(),
            thermal: Self.thermal(info.thermalState),
            uptime: info.systemUptime,
            processes: ProcessLister.group(try ProcessLister.list())
        )
    }

    // MARK: - CPU

    struct CPUTicks { var busy: UInt64; var total: UInt64 }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Ordine: user, system, idle, nice
        let t = info.cpu_ticks
        let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    static func cpuUsage(from a: CPUTicks?, to b: CPUTicks?) -> Double {
        guard let a, let b, b.total > a.total else { return 0 }
        return Double(b.busy - a.busy) / Double(b.total - a.total) * 100
    }

    // MARK: - Memoria

    static func memory() -> MemoryInfo {
        let total = ProcessInfo.processInfo.physicalMemory
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var used: UInt64 = 0, cached: UInt64 = 0, compressed: UInt64 = 0
        if result == KERN_SUCCESS {
            let page = UInt64(pageSize)
            // Stessa formula di Monitoraggio Attività.
            let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
            compressed = UInt64(stats.compressor_page_count) * page
            used = (app + UInt64(stats.wire_count)) * page + compressed
            cached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
        }

        return MemoryInfo(totalBytes: total, usedBytes: min(used, total), cachedBytes: cached,
                          compressedBytes: compressed, swapUsedBytes: swapUsed(), pressure: pressure())
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    // MARK: - Temperatura

    static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
