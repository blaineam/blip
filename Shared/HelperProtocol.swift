import Foundation

// MARK: - Constants

enum HelperConstants {
    static let appGroupID = "group.com.blainemiller.Blip"
    static let portFileName = "bliphelper_port"
    static let helperBundleID = "com.blainemiller.BlipHelper"

    /// Returns the App Group container URL, or a fallback in ~/Library/Application Support.
    static var sharedContainerURL: URL {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return url
        }
        // Fallback for non-sandboxed builds or missing App Group entitlement
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fallback = appSupport.appendingPathComponent("BlipShared")
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Path where the helper writes its TCP port on startup.
    static var portFileURL: URL {
        sharedContainerURL.appendingPathComponent(portFileName)
    }
}

// MARK: - IPC Message Types

struct HelperRequest: Codable, Sendable {
    var type: String // "poll"
    var token: String // TOTP token
}

struct HelperResponse: Codable, Sendable {
    var type: String // "snapshot" or "error"
    var token: String? // TOTP token for response validation
    var data: HelperSnapshot?
    var message: String? // error message
}

// MARK: - Helper Snapshot (privileged data the sandbox blocks)

struct HelperSnapshot: Codable, Sendable {
    // Fan/thermal data (entire subsystem blocked by sandbox)
    var fans: [HelperFan]
    var cpuTemperature: Double?
    var gpuTemperature: Double?

    // GPU utilization (name/cores available via Metal, but utilization needs IOKit)
    var gpuUtilization: Double

    // Disk I/O speeds (volume space is fine, but IOKit throughput is blocked)
    var diskReadBytesPerSec: UInt64
    var diskWriteBytesPerSec: UInt64
    var diskTotalBytesRead: UInt64
    var diskTotalBytesWritten: UInt64
    var smartStatus: String

    // Battery health details (basic charge/state available, health needs IOKit registry)
    var batteryHealth: Double?
    var batteryCycleCount: Int?
    var batteryCondition: String?
    var batteryTemperature: Double?

    // Process list (proc_* APIs blocked in sandbox)
    var topProcessesByCPU: [HelperProcess]
    var topProcessesByMemory: [HelperProcess]

    var timestamp: Date
}

struct HelperFan: Codable, Sendable {
    var id: Int
    var name: String
    var currentRPM: Int
    var minRPM: Int
    var maxRPM: Int
}

struct HelperProcess: Codable, Sendable {
    var pid: Int32
    var name: String
    var cpu: Double
    var memory: UInt64
}

// MARK: - TCP Framing

/// Length-prefixed message framing for TCP.
/// Format: [4-byte big-endian length][JSON payload]
enum MessageFraming {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let json = try JSONEncoder().encode(value)
        var length = UInt32(json.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        return frame
    }

    /// Extract length from a 4-byte header.
    static func decodeLength(from header: Data) -> UInt32? {
        guard header.count >= 4 else { return nil }
        return header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
}
