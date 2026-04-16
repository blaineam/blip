import Foundation
import Combine
import Darwin
import IOKit
import SwiftUI

/// Central coordinator that polls all hardware monitors on a timer
/// and publishes unified snapshots for the UI layer.
///
/// For privileged data (SMC, IOKit, proc_*), the in-process monitors
/// are tried first. If they return empty results (e.g. when sandboxed),
/// the HelperClient fills in the gaps from BlipHelper over TCP.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var cpuHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)
    @Published var memoryHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)
    @Published var gpuHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)
    @Published var diskReadHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)
    @Published var diskWriteHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)
    @Published var netDownHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)
    @Published var netUpHistory = HistoryBuffer<Double>(capacity: 60, defaultValue: 0)

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let diskMonitor = DiskMonitor()
    private let gpuMonitor = GPUMonitor()
    private let networkMonitor = NetworkMonitor()
    private let batteryMonitor = BatteryMonitor()
    private let fanMonitor = FanMonitor()
    private let processMonitor = ProcessMonitor()

    /// Helper client for privileged data when running sandboxed.
    let helperClient = HelperClient()

    private var pollTask: Task<Void, Never>?
    private var diskPollCount = 0
    private var cachedModelName: String?
    @AppStorage("pingTarget") private var pingTarget: String = "1.1.1.1"

    /// Polling interval in seconds
    let interval: TimeInterval = 2.0

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            // Do an initial read immediately
            await self.poll()
            // Then poll on interval
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.interval))
                guard !Task.isCancelled else { break }
                await self.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        // Pass user's ping target preference to network monitor
        networkMonitor.pingTarget = pingTarget.isEmpty ? "1.1.1.1" : pingTarget

        // Run fast monitors concurrently
        async let cpuRead = Task.detached { [cpuMonitor] in cpuMonitor.read() }.value
        async let memRead = Task.detached { [memoryMonitor] in memoryMonitor.read() }.value
        async let netRead = Task.detached { [networkMonitor] in networkMonitor.read() }.value
        async let gpuRead = Task.detached { [gpuMonitor] in gpuMonitor.read() }.value
        async let battRead = batteryMonitor.read()
        async let fanRead = fanMonitor.read()
        async let procRead = Task.detached { [processMonitor] in await processMonitor.read() }.value

        // Also poll the helper (no-op if helper isn't running)
        await helperClient.poll()
        let helper = helperClient.latestSnapshot

        let cpu = await cpuRead
        let memory = await memRead
        let network = await netRead
        var gpu = await gpuRead
        var battery = await battRead
        var fans = await fanRead
        let procs = await procRead

        // Disk is slow — poll every 5th cycle (10 seconds)
        diskPollCount += 1
        var disk: DiskStats
        if diskPollCount % 5 == 1 {
            disk = await Task.detached { [diskMonitor] in diskMonitor.read() }.value
        } else {
            disk = snapshot.disk
        }

        // Merge helper data for privileged metrics.
        // In-process monitors succeed when unsandboxed; when sandboxed they
        // return empty/zero and the helper fills in the gaps.
        var topByCPU = procs.byCPU
        var topByMemory = procs.byMemory

        if let h = helper {
            // Fans/thermal: use helper if in-process SMC returned nothing
            if fans.fans.isEmpty && !h.fans.isEmpty {
                fans.fans = h.fans.map { FanInfo(id: $0.id, name: $0.name, currentRPM: $0.currentRPM, minRPM: $0.minRPM, maxRPM: $0.maxRPM) }
            }
            if fans.cpuTemperature == nil { fans.cpuTemperature = h.cpuTemperature }
            if fans.gpuTemperature == nil { fans.gpuTemperature = h.gpuTemperature }

            // GPU utilization: use helper if in-process IOKit returned 0
            if gpu.utilization == 0 && h.gpuUtilization > 0 {
                gpu.utilization = h.gpuUtilization
            }

            // Disk I/O: use helper if in-process returned 0
            if disk.readBytesPerSec == 0 && disk.writeBytesPerSec == 0 {
                disk.readBytesPerSec = h.diskReadBytesPerSec
                disk.writeBytesPerSec = h.diskWriteBytesPerSec
                disk.totalBytesRead = h.diskTotalBytesRead
                disk.totalBytesWritten = h.diskTotalBytesWritten
            }
            if disk.smartStatus.isEmpty && !h.smartStatus.isEmpty {
                disk.smartStatus = h.smartStatus
            }

            // Battery health: use helper if in-process returned defaults
            if battery.health == 0 { battery.health = h.batteryHealth ?? 0 }
            if battery.cycleCount == 0 { battery.cycleCount = h.batteryCycleCount ?? 0 }
            if battery.condition.isEmpty { battery.condition = h.batteryCondition ?? "" }
            if battery.temperature == 0 { battery.temperature = h.batteryTemperature ?? 0 }

            // Processes: use helper if in-process proc_* returned empty
            if topByCPU.isEmpty && !h.topProcessesByCPU.isEmpty {
                topByCPU = h.topProcessesByCPU.map {
                    ProcessInfo(id: $0.pid, name: $0.name, cpu: $0.cpu, memory: $0.memory, icon: nil)
                }
            }
            if topByMemory.isEmpty && !h.topProcessesByMemory.isEmpty {
                topByMemory = h.topProcessesByMemory.map {
                    ProcessInfo(id: $0.pid, name: $0.name, cpu: $0.cpu, memory: $0.memory, icon: nil)
                }
            }
        }

        // System info (uptime, thermal, self-usage)
        let sysInfo = readSystemInfo()

        var newSnapshot = SystemSnapshot()
        newSnapshot.cpu = cpu
        newSnapshot.memory = memory
        newSnapshot.disk = disk
        newSnapshot.gpu = gpu
        newSnapshot.network = network
        newSnapshot.battery = battery
        newSnapshot.fans = fans
        newSnapshot.system = sysInfo
        newSnapshot.topProcessesByCPU = topByCPU
        newSnapshot.topProcessesByMemory = topByMemory
        newSnapshot.timestamp = Date()

        snapshot = newSnapshot
        cpuHistory.append(cpu.totalUsage)
        memoryHistory.append(memory.usagePercent)
        gpuHistory.append(gpu.utilization)
        diskReadHistory.append(Double(disk.readBytesPerSec))
        diskWriteHistory.append(Double(disk.writeBytesPerSec))
        netDownHistory.append(Double(network.downloadSpeed))
        netUpHistory.append(Double(network.uploadSpeed))
    }

    private func readSystemInfo() -> SystemInfo {
        var info = SystemInfo()

        // Uptime
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 {
            info.uptime = Date().timeIntervalSince1970 - Double(boottime.tv_sec)
        }

        // Thermal state
        let thermalState = Foundation.ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .nominal: info.thermalLevel = .nominal
        case .fair: info.thermalLevel = .fair
        case .serious: info.thermalLevel = .serious
        case .critical: info.thermalLevel = .critical
        @unknown default: info.thermalLevel = .nominal
        }

        // Mac model — use cached marketing name from system_profiler
        if let cached = cachedModelName {
            info.macModel = cached
        } else {
            // Run system_profiler once to get the marketing model name
            let modelName = Self.fetchMarketingModelName()
            cachedModelName = modelName
            info.macModel = modelName
        }

        // macOS version
        let osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        info.macOSVersion = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Blip's own resource usage
        var rusage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &rusage) { ptr in
            ptr.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rusagePtr)
            }
        }
        if result == 0 {
            info.blipMemoryMB = Double(rusage.ri_phys_footprint) / 1_048_576
        }

        return info
    }

    /// Fetches the marketing model name via system_profiler (e.g. "MacBook Pro (16-inch, Nov 2024)")
    private static func fetchMarketingModelName() -> String {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["SPHardwareDataType"] as? [[String: Any]],
               let first = items.first {
                let modelName = first["machine_name"] as? String ?? ""
                let chipType = first["chip_type"] as? String ?? ""
                if !modelName.isEmpty && !chipType.isEmpty {
                    return "\(modelName) (\(chipType))"
                } else if !modelName.isEmpty {
                    return modelName
                }
            }
        } catch {
            // Fall through to sysctl fallback
        }
        // Fallback to hw.model
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            return String(decoding: model.prefix(size).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return "Mac"
    }
}
