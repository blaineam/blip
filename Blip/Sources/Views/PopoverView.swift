import SwiftUI

/// Main popover content showing overview rows.
/// Hover triggers detail panel via a separate NSPanel managed by AppDelegate.
struct PopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("accentColorOverride") private var colorOverride: String = ""
    #if APPSTORE
    private var helperConnected: Bool { monitor.helperClient.isConnected }
    #endif

    /// Callback when a section is hovered — AppDelegate handles showing the detail window.
    var onHoverSection: ((PopoverSection?) -> Void)?
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            overviewRow(.cpu)
            overviewRow(.memory)
            overviewRow(.disk)
            overviewRow(.network)
            #if APPSTORE
            if helperConnected {
                overviewRow(.gpu)
            }
            #else
            overviewRow(.gpu)
            #endif
            overviewRow(.thermal)

            if monitor.snapshot.battery.isPresent {
                overviewRow(.battery)
            }

            Divider()
                .padding(.vertical, 4)

            // System info footer
            VStack(spacing: 3) {
                if !monitor.snapshot.system.macModel.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(monitor.snapshot.system.macModel)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)

                    HStack(spacing: 6) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(monitor.snapshot.system.macOSVersion)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(Fmt.uptime(monitor.snapshot.system.uptime))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)

                HStack {
                    Text("Blip v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") · \(String(format: "%.1f", monitor.snapshot.system.blipMemoryMB)) MB")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                    Spacer()
                    Button {
                        onOpenSettings?()
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 6)
        }
        .frame(width: 260)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
    }

    @ViewBuilder
    private func overviewRow(_ section: PopoverSection) -> some View {
        Group {
            switch section {
            case .cpu:
                OverviewRow(
                    icon: "cpu",
                    label: "CPU",
                    value: Fmt.percent(monitor.snapshot.cpu.totalUsage),
                    percent: monitor.snapshot.cpu.totalUsage,
                    color: .blue
                )
            case .memory:
                OverviewRow(
                    icon: "memorychip",
                    label: "Memory",
                    value: Fmt.percent(monitor.snapshot.memory.usagePercent),
                    percent: monitor.snapshot.memory.usagePercent,
                    color: .green
                )
            case .disk:
                OverviewRow(
                    icon: "internaldrive",
                    label: "Disk",
                    value: Fmt.percent(monitor.snapshot.disk.primaryUsagePercent),
                    percent: monitor.snapshot.disk.primaryUsagePercent,
                    color: .orange
                )
            case .network:
                HStack(spacing: 8) {
                    Image(systemName: monitor.snapshot.network.isConnected ? "wifi" : "wifi.slash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.cyan)
                        .frame(width: 16)
                    Text("Network")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 60, alignment: .leading)
                    // Occupy same space as UsageBar(60) + value(40) = 108 with spacing
                    HStack(spacing: 4) {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 7))
                                .foregroundStyle(.green)
                            Text(Fmt.shortSpeed(monitor.snapshot.network.downloadSpeed))
                                .font(.system(size: 9, design: .monospaced))
                        }
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 7))
                                .foregroundStyle(.blue)
                            Text(Fmt.shortSpeed(monitor.snapshot.network.uploadSpeed))
                                .font(.system(size: 9, design: .monospaced))
                        }
                    }
                    .frame(width: 108, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            case .gpu:
                OverviewRow(
                    icon: "rectangle.3.group",
                    label: "GPU",
                    value: Fmt.percent(monitor.snapshot.gpu.utilization),
                    percent: monitor.snapshot.gpu.utilization,
                    color: .purple
                )
            case .thermal:
                HStack(spacing: 8) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(thermalColor)
                        .frame(width: 16)
                    Text("Thermal")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 60, alignment: .leading)
                    Text(monitor.snapshot.system.thermalLevel.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(thermalColor)
                        .frame(width: 108, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            case .battery:
                OverviewRow(
                    icon: "battery.75",
                    label: "Battery",
                    value: Fmt.percent(monitor.snapshot.battery.level),
                    percent: monitor.snapshot.battery.level,
                    color: .green
                )
            }
        }
        .background(Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            onHoverSection?(hovering ? section : nil)
        }
    }

    private var thermalColor: Color {
        switch monitor.snapshot.system.thermalLevel {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Section Enum (shared with AppDelegate)

enum PopoverSection: String, CaseIterable {
    case cpu, memory, disk, network, gpu, thermal, battery
}
