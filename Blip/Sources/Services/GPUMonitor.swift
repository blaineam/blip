import Foundation
import IOKit
@preconcurrency import Metal

final class GPUMonitor: Sendable {
    /// Static GPU metadata fetched once at init
    private let gpuName: String
    private let gpuCoreCount: Int

    init() {
        let device = MTLCreateSystemDefaultDevice()
        gpuName = device?.name ?? "Apple GPU"

        // Core count from sysctl (preferred) or IOKit fallback
        var cores: Int = 0
        var gpuCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("machdep.gpu.core_count", &gpuCores, &size, nil, 0) == 0 {
            cores = Int(gpuCores)
        }
        if cores == 0 {
            // One-time IOKit lookup for core count
            var iterator: io_iterator_t = 0
            if let matching = IOServiceMatching("IOAccelerator"),
               IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
                defer { IOObjectRelease(iterator) }
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
                    var properties: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                       let dict = properties?.takeRetainedValue() as? [String: Any],
                       let c = dict["gpu-core-count"] as? NSNumber {
                        cores = c.intValue
                        break
                    }
                }
            }
        }
        gpuCoreCount = cores
    }

    /// Known IOKit utilization key names — Apple may add new ones on future hardware.
    private static let utilizationKeys = [
        "Device Utilization %",
        "GPU Activity(%)",
        "GPU Core Utilization %",
    ]

    func read() -> GPUStats {
        var stats = GPUStats()
        stats.name = gpuName
        stats.coreCount = gpuCoreCount

        // Only poll utilization — the dynamic value
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return stats
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let perfStats = dict["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            // Try known utilization keys — future hardware may use a new name
            for key in Self.utilizationKeys {
                if let value = perfStats[key] as? NSNumber {
                    stats.utilization = value.doubleValue
                    break
                }
            }
        }

        return stats
    }
}
