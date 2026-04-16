import Foundation
import IOKit

final class FanMonitor: Sendable {
    func read() async -> FanStats {
        var stats = FanStats()

        if SMC.open() {
            // Read temperatures via SMC
            stats.cpuTemperature = SMC.readCPUTemperature()
            stats.gpuTemperature = SMC.readGPUTemperature()

            let fanCount = SMC.readFanCount()
            // Sanity: fan count should be 0-10
            guard fanCount >= 0 && fanCount <= 10 else { return stats }
            for i in 0..<fanCount {
                let rpm = SMC.readFanRPM(fan: i)
                let minRPM = SMC.readFanMin(fan: i)
                let maxRPM = SMC.readFanMax(fan: i)
                // Validate: RPM should be in a reasonable range
                let validRPM = (rpm >= 0 && rpm <= 10_000) ? rpm : 0
                let fan = FanInfo(
                    id: i,
                    name: "Fan \(i + 1)",
                    currentRPM: validRPM,
                    minRPM: (minRPM >= 0 && minRPM <= 10_000) ? minRPM : 0,
                    maxRPM: (maxRPM >= 0 && maxRPM <= 10_000) ? maxRPM : 6000
                )
                stats.fans.append(fan)
            }
        }

        // Fallback: try IOKit HIDSystem for fan data if SMC returned nothing
        if stats.fans.isEmpty {
            let ioKitFans = readFansFromIOKit()
            if !ioKitFans.isEmpty {
                stats.fans = ioKitFans
            }
        }

        return stats
    }

    /// Reads fan data from IOKit AppleSmartBattery / ACPI fans as a fallback
    private func readFansFromIOKit() -> [FanInfo] {
        var fans: [FanInfo] = []

        // Try to find fan services via IOKit
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSmartBatteryManager")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else { return fans }
        defer { IOObjectRelease(iterator) }

        // Also try reading from powermetrics-style approach via thermal sensors
        // On Apple Silicon, fan info may be under IOHIDSystem or ACPI
        let fanService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMCKeysEndpoint")
        )
        if fanService != 0 {
            defer { IOObjectRelease(fanService) }
            // Try to get properties
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(fanService, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = properties?.takeRetainedValue() as? [String: Any] {
                // Look for fan-related keys
                for (key, value) in dict {
                    if key.contains("Fan") || key.contains("fan"),
                       let rpm = value as? Int, rpm > 0 {
                        fans.append(FanInfo(id: fans.count, name: key, currentRPM: rpm, minRPM: 0, maxRPM: 6000))
                    }
                }
            }
        }

        return fans
    }
}
