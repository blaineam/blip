import SwiftUI

/// Menu bar view supporting stacked (compact) and horizontal (wide) layouts.
struct StatusItemView: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("accentColorOverride") private var colorOverride: String = ""
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showNetworkDot") private var showNetworkDot = true
    @AppStorage("showMeasurementLabels") private var showMeasurementLabels = true
    @AppStorage("showValueLabels") private var showValueLabels = true
    @AppStorage("menuBarLayout") private var menuBarLayout: String = "horizontal"
    @AppStorage("colorizeUtilization") private var colorizeUtilization = true

    var body: some View {
        Group {
            if menuBarLayout == "horizontal" {
                horizontalLayout
            } else {
                stackedLayout
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 22)
        .fixedSize()
    }

    // MARK: - Stacked Layout (compact vertical bars)

    private var stackedLayout: some View {
        HStack(alignment: .center, spacing: 3) {
            if showMeasurementLabels {
                VStack(alignment: .trailing, spacing: 2) {
                    if showCPU { stackedLabel("CPU", color: .blue) }
                    if showMemory { stackedLabel("MEM", color: .green) }
                    if showDisk { stackedLabel(" HD", color: .orange) }
                }
            }

            VStack(spacing: 3) {
                if showCPU { tinyBar(value: monitor.snapshot.cpu.totalUsage, color: .blue) }
                if showMemory { tinyBar(value: monitor.snapshot.memory.usagePercent, color: .green) }
                if showDisk { tinyBar(value: monitor.snapshot.disk.primaryUsagePercent, color: .orange) }
            }

            if showValueLabels {
                VStack(alignment: .trailing, spacing: 2) {
                    if showCPU { tinyPercent(monitor.snapshot.cpu.totalUsage, color: .blue) }
                    if showMemory { tinyPercent(monitor.snapshot.memory.usagePercent, color: .green) }
                    if showDisk { tinyPercent(monitor.snapshot.disk.primaryUsagePercent, color: .orange) }
                }
            }

            networkDot
        }
    }

    // MARK: - Horizontal Layout (wide, side-by-side)

    private var horizontalLayout: some View {
        HStack(spacing: 8) {
            if showCPU { horizontalItem(label: "CPU", value: monitor.snapshot.cpu.totalUsage, color: .blue) }
            if showMemory { horizontalItem(label: "MEM", value: monitor.snapshot.memory.usagePercent, color: .green) }
            if showDisk { horizontalItem(label: "HD", value: monitor.snapshot.disk.primaryUsagePercent, color: .orange) }
            networkDot
        }
    }

    private func horizontalItem(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            if showMeasurementLabels {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(resolvedColor(color))
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(resolvedColor(color).opacity(0.25))
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(barColor(value, base: color))
                    .frame(width: 28 * min(value / 100, 1))
            }
            .frame(width: 28, height: 4)

            if showValueLabels {
                Text(String(format: "%2.0f", value))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .frame(width: 18, alignment: .trailing)
            }
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var networkDot: some View {
        if showNetworkDot && monitor.snapshot.network.isConnected {
            Circle()
                .fill(resolvedColor(.green))
                .frame(width: 4, height: 4)
        }
    }

    private func tinyBar(value: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(resolvedColor(color).opacity(0.25))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor(value, base: color))
                .frame(width: 20 * min(value / 100, 1))
        }
        .frame(width: 20, height: 3)
    }

    private func stackedLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 6, weight: .semibold, design: .monospaced))
            .foregroundStyle(resolvedColor(color))
            .frame(height: 5)
    }

    private func tinyPercent(_ value: Double, color: Color) -> some View {
        Text(String(format: "%2.0f", value))
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .foregroundStyle(resolvedColor(color))
            .frame(height: 5)
    }

    private func barColor(_ value: Double, base: Color) -> Color {
        guard colorizeUtilization else { return resolvedColor(base) }
        if value > 90 { return .red }
        if value > 70 { return .orange }
        return resolvedColor(base)
    }

    private func resolvedColor(_ fallback: Color) -> Color {
        if colorOverride == "MENU_BAR" {
            return .primary
        }
        guard !colorOverride.isEmpty else { return fallback }
        return Color(hex: colorOverride) ?? fallback
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
