import Foundation
import IOKit.ps

final class BatteryMonitor: Sendable {
    func read() async -> BatteryStats {
        var stats = BatteryStats()

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            return stats
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            stats.isPresent = true

            if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
               maxCapacity > 0 {
                stats.level = Double(capacity) / Double(maxCapacity) * 100
            }

            if let charging = info[kIOPSIsChargingKey] as? Bool {
                stats.isCharging = charging
            }

            if let source = info[kIOPSPowerSourceStateKey] as? String {
                stats.powerSource = source == kIOPSACPowerValue ? "AC Power" : "Battery"
            }

            if let timeRemaining = info[kIOPSTimeToEmptyKey] as? Int {
                stats.timeRemaining = timeRemaining
            }
        }

        // Read battery health and cycle count from IOKit registry
        await readBatteryHealth(&stats)

        return stats
    }

    /// IOKit service names to try for battery health — Apple may rename on future hardware.
    private static let batteryServiceNames = [
        "AppleSmartBattery",
        "AppleSmartBatteryCase",
    ]

    /// Registry keys for capacity, ordered by preference.
    private static let capacityKeys = ["NominalChargeCapacity", "AppleRawMaxCapacity", "MaxCapacity"]
    private static let designCapacityKeys = ["DesignCapacity", "DesignCycleCount9C"]

    private func readBatteryHealth(_ stats: inout BatteryStats) async {
        var service: io_service_t = 0
        for name in Self.batteryServiceNames {
            service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(name)
            )
            if service != 0 { break }
        }
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return
        }

        if let cycleCount = dict["CycleCount"] as? Int {
            stats.cycleCount = cycleCount
        }

        // Try capacity keys in preference order
        let currentCap = Self.capacityKeys.lazy.compactMap { dict[$0] as? Int }.first
        let designCap = Self.designCapacityKeys.lazy.compactMap { dict[$0] as? Int }.first
        if let current = currentCap, let design = designCap, design > 0 {
            let health = Double(current) / Double(design) * 100
            // Sanity check: health should be 0-200% range
            if health > 0 && health < 200 {
                stats.health = health
            }
        }

        // Battery condition (Normal, Service, etc.)
        if let condition = dict["BatteryHealthCondition"] as? String {
            stats.condition = condition
        } else {
            stats.condition = "Normal"
        }

        if let temp = dict["Temperature"] as? Int {
            let celsius = Double(temp) / 100.0
            // Sanity: battery temp should be -20 to 80 C
            if celsius > -20 && celsius < 80 {
                stats.temperature = celsius
            }
        }
    }
}
