import Foundation
import IOKit

final class DiskMonitor: @unchecked Sendable {
    private var previousReadBytes: UInt64 = 0
    private var previousWriteBytes: UInt64 = 0
    private var previousTimestamp: Date?

    private var cachedSmartStatus: String?

    func read() -> DiskStats {
        var stats = DiskStats()
        let fileManager = FileManager.default

        // Get mounted volume URLs
        guard let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey],
            options: [.skipHiddenVolumes]
        ) else {
            return stats
        }

        for url in volumeURLs {
            guard let resources = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ]) else { continue }

            let name = resources.volumeName ?? url.lastPathComponent
            let total = UInt64(resources.volumeTotalCapacity ?? 0)
            let free = UInt64(resources.volumeAvailableCapacityForImportantUsage ?? 0)

            guard total > 0 else { continue }

            let volume = VolumeInfo(
                name: name,
                mountPoint: url.path,
                totalBytes: total,
                freeBytes: free
            )
            stats.volumes.append(volume)
        }

        // Sort: root volume first, then alphabetically
        stats.volumes.sort { a, b in
            if a.mountPoint == "/" { return true }
            if b.mountPoint == "/" { return false }
            return a.name < b.name
        }

        // Read disk I/O from IOKit
        readDiskIO(&stats)

        // SMART status (cached, only read once)
        if let cached = cachedSmartStatus {
            stats.smartStatus = cached
        } else {
            let smart = Self.readSmartStatus()
            cachedSmartStatus = smart
            stats.smartStatus = smart
        }

        return stats
    }

    private static func readSmartStatus() -> String {
        let task = Foundation.Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["info", "disk0"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            for line in output.components(separatedBy: "\n") {
                if line.contains("SMART Status") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        return parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        } catch {}
        return ""
    }

    /// IOKit class names for disk I/O — Apple may change on future storage controllers.
    private static let diskIOServiceNames = [
        "IOBlockStorageDriver",
        "IONVMeBlockStorageDriver",
    ]

    private func readDiskIO(_ stats: inout DiskStats) {
        var iterator: io_iterator_t = 0
        var matched = false
        for serviceName in Self.diskIOServiceNames {
            guard let matching = IOServiceMatching(serviceName) else { continue }
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
                matched = true
                break
            }
        }
        guard matched else { return }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let ioStats = dict["Statistics"] as? [String: Any] else {
                continue
            }

            if let read = ioStats["Bytes (Read)"] as? UInt64 {
                totalRead += read
            }
            if let write = ioStats["Bytes (Write)"] as? UInt64 {
                totalWrite += write
            }
        }

        // Expose cumulative totals since boot
        stats.totalBytesRead = totalRead
        stats.totalBytesWritten = totalWrite

        let now = Date()
        if let prev = previousTimestamp {
            let interval = now.timeIntervalSince(prev)
            if interval > 0 {
                stats.readBytesPerSec = totalRead > previousReadBytes
                    ? UInt64(Double(totalRead - previousReadBytes) / interval)
                    : 0
                stats.writeBytesPerSec = totalWrite > previousWriteBytes
                    ? UInt64(Double(totalWrite - previousWriteBytes) / interval)
                    : 0
            }
        }
        previousReadBytes = totalRead
        previousWriteBytes = totalWrite
        previousTimestamp = now
    }
}
