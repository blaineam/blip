import Foundation
import Combine
import Darwin
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
    /// Only activated when the app is inside an App Sandbox.
    let helperClient = HelperClient()

    /// True when the app is running inside App Sandbox (MAS version).
    /// The direct-download version is unsandboxed and never needs the helper.
    private let isSandboxed: Bool = {
        Foundation.ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()

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

        // Poll the helper only when sandboxed (MAS version).
        // The direct-download version reads everything in-process.
        if isSandboxed {
            await helperClient.poll()
        }
        let helper = isSandboxed ? helperClient.latestSnapshot : nil

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
                    ProcessInfo(id: $0.pid, name: $0.name, cpu: $0.cpu, memory: $0.memory, icon: $0.icon)
                }
            }
            if topByMemory.isEmpty && !h.topProcessesByMemory.isEmpty {
                topByMemory = h.topProcessesByMemory.map {
                    ProcessInfo(id: $0.pid, name: $0.name, cpu: $0.cpu, memory: $0.memory, icon: $0.icon)
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

        // Mac model — try helper's marketing name first (MAS build),
        // then fall back to in-process fetch
        if let cached = cachedModelName {
            info.macModel = cached
        } else if let helperModel = helperClient.latestSnapshot?.macModelName, !helperModel.isEmpty {
            cachedModelName = helperModel
            info.macModel = helperModel
        } else {
            let modelName = Self.fetchMarketingModelName()
            cachedModelName = modelName
            info.macModel = modelName
        }

        // macOS version
        let osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        info.macOSVersion = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Blip's own memory footprint
        #if APPSTORE
        // Use task_info (public Mach API, sandbox-safe)
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            info.blipMemoryMB = Double(vmInfo.phys_footprint) / 1_048_576
        }
        #else
        // proc_pid_rusage (private API, not permitted on App Store)
        var rusage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &rusage) { ptr in
            ptr.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rusagePtr)
            }
        }
        if result == 0 {
            info.blipMemoryMB = Double(rusage.ri_phys_footprint) / 1_048_576
        }
        #endif

        return info
    }

    /// Fetches the marketing model name.
    /// On the direct-download version, uses system_profiler for the full name.
    /// On the App Store version, uses the sysctl hw.model fallback only.
    private static func fetchMarketingModelName() -> String {
        #if !APPSTORE
        // system_profiler subprocess — not permitted on App Store
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
        #endif
        // hw.model via sysctl (public API, safe for App Store)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            let identifier = String(decoding: model.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // Try to resolve the marketing name from the identifier
            if let marketing = Self.modelLookup[identifier] {
                return marketing
            }
            return identifier
        }
        return "Mac"
    }

    /// Compact model lookup: "id:product,chip,year" tuples decoded at init.
    /// Keeps binary small — ~1.5 KB vs ~3.5 KB for full string dictionary.
    private static let modelLookup: [String: String] = {
        // Format: "id=type,size,chip,year" — decoded into "Type Size (Chip, Year)"
        // Types: A=MacBook Air, P=MacBook Pro, m=Mac mini, i=iMac, S=Mac Studio, R=Mac Pro
        let entries: [(String, String)] = [
            // M1
            ("MacBookAir10,1", "A,13\",M1,2020"), ("MacBookPro17,1", "P,13\",M1,2020"),
            ("MacBookPro18,1", "P,16\",M1 Pro,2021"), ("MacBookPro18,2", "P,16\",M1 Max,2021"),
            ("MacBookPro18,3", "P,14\",M1 Pro,2021"), ("MacBookPro18,4", "P,14\",M1 Max,2021"),
            ("Macmini9,1", "m,,M1,2020"),
            ("iMac21,1", "i,24\",M1,2021"), ("iMac21,2", "i,24\",M1,2021"),
            ("Mac13,1", "S,,M1 Max,2022"), ("Mac13,2", "S,,M1 Ultra,2022"),
            // M2
            ("Mac14,2", "A,13\",M2,2022"), ("Mac14,15", "A,15\",M2,2023"),
            ("Mac14,7", "P,13\",M2,2022"),
            ("Mac14,5", "P,14\",M2 Pro,2023"), ("Mac14,9", "P,14\",M2 Max,2023"),
            ("Mac14,6", "P,16\",M2 Pro,2023"), ("Mac14,10", "P,16\",M2 Max,2023"),
            ("Mac14,3", "m,,M2,2023"), ("Mac14,12", "m,,M2 Pro,2023"),
            ("Mac14,8", "R,,M2 Ultra,2023"),
            ("Mac14,13", "S,,M2 Max,2023"), ("Mac14,14", "S,,M2 Ultra,2023"),
            // M3
            ("Mac15,3", "P,14\",M3,2023"),
            ("Mac15,12", "A,13\",M3,2024"), ("Mac15,13", "A,15\",M3,2024"),
            ("Mac15,4", "i,24\",M3,2023"), ("Mac15,5", "i,24\",M3,2023"),
            ("Mac15,6", "P,14\",M3 Pro,2023"), ("Mac15,10", "P,14\",M3 Max,2023"),
            ("Mac15,8", "P,14\",M3 Max,2023"),
            ("Mac15,7", "P,16\",M3 Pro,2023"), ("Mac15,11", "P,16\",M3 Max,2023"),
            ("Mac15,9", "P,16\",M3 Max,2023"), ("Mac15,14", "S,,M3 Ultra,2025"),
            // M4
            ("Mac16,1", "P,14\",M4,2024"),
            ("Mac16,8", "P,14\",M4 Pro,2024"), ("Mac16,6", "P,14\",M4 Max,2024"),
            ("Mac16,7", "P,16\",M4 Pro,2024"), ("Mac16,5", "P,16\",M4 Max,2024"),
            ("Mac16,2", "i,24\",M4,2024"), ("Mac16,3", "i,24\",M4,2024"),
            ("Mac16,10", "m,,M4,2024"), ("Mac16,11", "m,,M4 Pro,2024"),
            ("Mac16,9", "S,,M4 Max,2025"),
            ("Mac16,12", "A,13\",M4,2025"), ("Mac16,13", "A,15\",M4,2025"),
        ]
        let types: [Character: String] = ["A": "MacBook Air", "P": "MacBook Pro", "m": "Mac mini", "i": "iMac", "S": "Mac Studio", "R": "Mac Pro"]
        var dict = [String: String](minimumCapacity: entries.count)
        for (id, spec) in entries {
            let parts = spec.split(separator: ",", omittingEmptySubsequences: false)
            let type = types[parts[0].first!] ?? "Mac"
            let size = parts[1].isEmpty ? "" : " \(parts[1])"
            dict[id] = "\(type)\(size) (\(parts[2]), \(parts[3]))"
        }
        return dict
    }()
}
