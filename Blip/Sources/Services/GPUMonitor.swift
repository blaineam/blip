import Foundation
#if !APPSTORE
import IOKit
#endif
@preconcurrency import Metal

final class GPUMonitor: Sendable {
    /// Static GPU metadata fetched once at init
    private let gpuName: String
    private let gpuCoreCount: Int

    init() {
        let device = MTLCreateSystemDefaultDevice()
        let name = device?.name ?? "Apple GPU"
        gpuName = name

        // Try IOKit first (direct download), then fall back to chip name lookup (App Store)
        var cores: Int = 0
        #if !APPSTORE
        // IOKit lookup for core count (undocumented IOAccelerator)
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
        #endif
        if cores == 0 {
            cores = Self.gpuCoresFromChipName(name)
        }
        gpuCoreCount = cores
    }

    /// Derive GPU core count from Metal device name (public API, sandbox-safe).
    private static func gpuCoresFromChipName(_ name: String) -> Int {
        let chipCores: [(String, Int)] = [
            ("M4 Max", 40), ("M4 Pro", 20), ("M4", 10),
            ("M3 Ultra", 76), ("M3 Max", 40), ("M3 Pro", 18), ("M3", 10),
            ("M2 Ultra", 76), ("M2 Max", 38), ("M2 Pro", 19), ("M2", 10),
            ("M1 Ultra", 64), ("M1 Max", 32), ("M1 Pro", 16), ("M1", 8),
        ]
        // Match longest chip name first (e.g. "M4 Pro" before "M4")
        for (chip, cores) in chipCores {
            if name.contains(chip) { return cores }
        }
        return 0
    }

    func read() -> GPUStats {
        var stats = GPUStats()
        stats.name = gpuName
        stats.coreCount = gpuCoreCount

        #if !APPSTORE
        // GPU utilization requires undocumented IOKit IOAccelerator properties.
        // On the App Store build, the helper provides this data instead.
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return stats
        }
        defer { IOObjectRelease(iterator) }

        let utilizationKeys = [
            "Device Utilization %",
            "GPU Activity(%)",
            "GPU Core Utilization %",
        ]

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

            for key in utilizationKeys {
                if let value = perfStats[key] as? NSNumber {
                    stats.utilization = value.doubleValue
                    break
                }
            }
        }
        #endif

        return stats
    }
}
