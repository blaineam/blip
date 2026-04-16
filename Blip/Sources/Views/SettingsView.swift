import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("accentColorOverride") private var colorOverride: String = ""
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showNetworkDot") private var showNetworkDot = true
    @AppStorage("showMeasurementLabels") private var showMeasurementLabels = true
    @AppStorage("showValueLabels") private var showValueLabels = true
    @AppStorage("menuBarLayout") private var menuBarLayout: String = "horizontal"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("pingTarget") private var pingTarget: String = "1.1.1.1"
    @AppStorage("colorizeUtilization") private var colorizeUtilization = true

    var helperClient: HelperClient?

    @State private var selectedTab: Int = 2
    @State private var selectedMode: ColorMode = .category
    @State private var customColor: Color = .blue
    @State private var helperConnected = false
    @State private var helperInstalled = false

    enum ColorMode: String, CaseIterable {
        case category = "Category Colors"
        case monochrome = "Monochrome"
        case custom = "Custom Color"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(1)

            menuBarTab
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
                .tag(2)
        }
        .frame(width: 440, height: 320)
        .onAppear {
            if colorOverride == "MENU_BAR" {
                selectedMode = .monochrome
            } else if colorOverride.isEmpty {
                selectedMode = .category
            } else {
                selectedMode = .custom
                if let c = Color(hex: colorOverride) {
                    customColor = c
                }
            }
            refreshHelperStatus()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            refreshHelperStatus()
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Section("Network") {
                HStack {
                    Text("Ping Target")
                    Spacer()
                    TextField("1.1.1.1", text: $pingTarget)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            #if APPSTORE
            if helperClient != nil {
                Section("Blip Helper") {
                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(helperConnected ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(helperConnected ? "Connected" : helperInstalled ? "Not Running" : "Not Installed")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !helperConnected {
                        Text("Install Blip Helper for fan speeds, temperatures, GPU utilization, disk I/O, battery health, and process monitoring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Download Blip Helper", destination: URL(string: "https://github.com/blaineam/blip/releases/latest")!)
                            .font(.caption)
                    }
                }
            }
            #endif

            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Website") {
                    Link("blip.wemiller.com", destination: URL(string: "https://blip.wemiller.com")!)
                        .font(.system(size: 12))
                }
                LabeledContent("GitHub") {
                    Link("blaineam/blip", destination: URL(string: "https://github.com/blaineam/blip")!)
                        .font(.system(size: 12))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appearanceTab: some View {
        Form {
            Section("Menu Bar Colors") {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(ColorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedMode) { _, newMode in
                    applyColorMode(newMode)
                }

                if selectedMode == .custom {
                    ColorPicker("Pick a color", selection: $customColor, supportsOpacity: false)
                        .onChange(of: customColor) { _, newColor in
                            colorOverride = newColor.hexString
                        }
                }
            }

            Section {
                HStack(spacing: 8) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    livePreview
                }
            }

            Section {
                switch selectedMode {
                case .category:
                    Text("Blue for CPU, green for memory, orange for disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .monochrome:
                    Text("All bars match the system menu bar icon color.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .custom:
                    Text("All bars use your chosen color.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Live Preview (mirrors actual menu bar layout)

    @ViewBuilder
    private var livePreview: some View {
        if menuBarLayout == "horizontal" {
            horizontalPreview
        } else {
            stackedPreview
        }
    }

    private var stackedPreview: some View {
        HStack(alignment: .center, spacing: 3) {
            if showMeasurementLabels {
                VStack(alignment: .trailing, spacing: 3) {
                    if showCPU { previewLabel("CPU") }
                    if showMemory { previewLabel("MEM") }
                    if showDisk { previewLabel(" HD") }
                }
            }

            VStack(spacing: 3) {
                if showCPU { previewTinyBar(fill: 0.45, color: resolvedPreviewColor(.blue)) }
                if showMemory { previewTinyBar(fill: 0.67, color: resolvedPreviewColor(.green)) }
                if showDisk { previewTinyBar(fill: 0.34, color: resolvedPreviewColor(.orange)) }
            }

            if showValueLabels {
                VStack(alignment: .trailing, spacing: 3) {
                    if showCPU { previewValue("45") }
                    if showMemory { previewValue("67") }
                    if showDisk { previewValue("34") }
                }
            }

            if showNetworkDot {
                Circle()
                    .fill(Color.green)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var horizontalPreview: some View {
        HStack(spacing: 8) {
            if showCPU { horizontalPreviewItem(label: "CPU", fill: 0.45, color: resolvedPreviewColor(.blue)) }
            if showMemory { horizontalPreviewItem(label: "MEM", fill: 0.67, color: resolvedPreviewColor(.green)) }
            if showDisk { horizontalPreviewItem(label: "HD", fill: 0.34, color: resolvedPreviewColor(.orange)) }
            if showNetworkDot {
                Circle()
                    .fill(Color.green)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func horizontalPreviewItem(label: String, fill: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            if showMeasurementLabels {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.25))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 28 * fill)
            }
            .frame(width: 28, height: 3)
            if showValueLabels {
                Text(String(format: "%2.0f", fill * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .frame(width: 18, alignment: .trailing)
            }
        }
    }

    private func previewTinyBar(fill: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color.opacity(0.25))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 20 * fill)
        }
        .frame(width: 20, height: 3)
    }

    private func previewLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 6, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 3)
    }

    private func previewValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 3)
    }

    private func resolvedPreviewColor(_ fallback: Color) -> Color {
        switch selectedMode {
        case .category: return fallback
        case .monochrome: return .primary
        case .custom: return customColor
        }
    }

    private func refreshHelperStatus() {
        guard let helperClient else { return }
        helperConnected = helperClient.isConnected
        helperInstalled = helperClient.isHelperInstalled
    }

    private func applyColorMode(_ mode: ColorMode) {
        switch mode {
        case .category:
            colorOverride = ""
        case .monochrome:
            colorOverride = "MENU_BAR"
        case .custom:
            colorOverride = customColor.hexString
        }
    }

    private var menuBarTab: some View {
        Form {
            Section("Visible Items") {
                Toggle("CPU", isOn: $showCPU)
                Toggle("Memory", isOn: $showMemory)
                Toggle("Disk", isOn: $showDisk)
                Toggle("Network Indicator", isOn: $showNetworkDot)
            }
            Section("Layout") {
                Picker("Menu Bar Style", selection: $menuBarLayout) {
                    Text("Stacked (compact)").tag("stacked")
                    Text("Horizontal (wide)").tag("horizontal")
                }
                .pickerStyle(.radioGroup)
            }
            Section("Display") {
                Toggle("Show Measurement Labels", isOn: $showMeasurementLabels)
                Toggle("Show Value Labels", isOn: $showValueLabels)
                Toggle("Colorize bars at high utilization", isOn: $colorizeUtilization)
            }

            Section {
                HStack(spacing: 8) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    livePreview
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Color to Hex

extension Color {
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
