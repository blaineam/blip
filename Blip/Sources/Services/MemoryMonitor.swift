import Foundation
import Darwin

final class MemoryMonitor: Sendable {
    func read() -> MemoryStats {
        var stats = MemoryStats()

        // Total physical memory
        stats.total = Foundation.ProcessInfo.processInfo.physicalMemory

        // VM statistics
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return stats }

        let pageSize = UInt64(vm_page_size)

        stats.wired = UInt64(vmStats.wire_count) * pageSize
        stats.compressed = UInt64(vmStats.compressor_page_count) * pageSize

        let internal_ = UInt64(vmStats.internal_page_count) * pageSize
        let purgeable = UInt64(vmStats.purgeable_count) * pageSize
        let external = UInt64(vmStats.external_page_count) * pageSize
        let free = UInt64(vmStats.free_count) * pageSize

        // Match Activity Monitor's definitions exactly:
        // App Memory = internal pages - purgeable pages
        stats.appMemory = internal_ > purgeable ? internal_ - purgeable : 0
        // Cached Files = Purgeable + External (file-backed pages)
        stats.cachedFiles = purgeable + external
        // Memory Used = App Memory + Wired + Compressed
        stats.used = stats.appMemory + stats.wired + stats.compressed
        // Free = what's left
        stats.free = stats.total > stats.used ? stats.total - stats.used : free

        // Memory pressure level from kernel
        var pressureLevel: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &pressureSize, nil, 0) == 0 {
            stats.pressureLevel = Int(pressureLevel)
        }

        // Swap usage via sysctl
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            stats.swapUsed = swapUsage.xsu_used
            stats.swapTotal = swapUsage.xsu_total
        }

        return stats
    }
}
