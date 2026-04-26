# Blip

**A featherlight macOS menu bar system monitor.** CPU, memory, disk, GPU, network, battery — all in a tiny, beautiful package.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![App Size](https://img.shields.io/badge/app-~2MB-purple)

---

## 💡 Why Blip?

Existing system monitors are either bloated, expensive, or missing key features. Blip takes the best ideas from iStats Menus and Stats Panel, strips away the fluff, and delivers a monitor that's:

- **Tiny** — ~2 MB app bundle, ~42 MB memory footprint
- **Fast** — async/await throughout, polls every 2 seconds
- **Pretty** — clean layout, smooth charts, hover detail panels
- **Focused** — system metrics only, no weather or clock widgets
- **Free** — open source under MIT, notarized releases on GitHub

## ✨ Features

| Category | Menu Bar | Detail Panel |
|----------|----------|-------------|
| **CPU** | Usage bar + percentage | Per-core bars, user/system/idle split, load averages (1m/5m/15m), P-core and E-core counts, top processes with accurate delta-based CPU and app icons |
| **Memory** | Usage bar + percentage | Total memory, active/wired/compressed/app breakdown, swap usage, memory pressure (factors in swap), top processes with accurate `phys_footprint` memory and app icons |
| **Disk** | Usage bar + percentage | All mounted volumes with space used/free, real-time read/write speeds, total data read/written since boot, I/O history chart with Y-axis labels |
| **Network** | Connectivity dot | Upload/download speeds, total bytes up/down since boot, WAN and router ping latency (configurable target), bandwidth history chart with Y-axis labels, all active interfaces (Wi-Fi + Ethernet), IPv4/IPv6, LAN IP, router IP, MAC address, WAN IP reveal, VPN detection (Tailscale, WireGuard), click-to-copy addresses |
| **GPU** | — | Apple Silicon GPU utilization, renderer name, GPU core count, historical usage chart |
| **Battery** | — | Charge %, health %, cycle count, temperature, time remaining, charging status |
| **Fans** | — | RPM per fan with min/max range bars, CPU and GPU temperatures |
| **System** | — | Mac model, macOS version, uptime, thermal state, Blip's own memory usage |

Plus:
- **Historical charts** — sparklines for CPU, memory, GPU; dual-line charts for disk I/O and network bandwidth with auto-scaled Y-axis labels
- **Live detail panels** — hover any row in the popover to reveal a detailed sub-panel that updates in real-time (like iStats Menus)
- **Two layouts** — horizontal (default, wide side-by-side) or stacked (compact vertical bars)
- **Customizable** — category colors, monochrome, or custom color picker; separate measurement and value label toggles; optional utilization colorization
- **Launch at login** — one toggle in settings

## 📦 Install

### Mac App Store

Blip is available on the Mac App Store as **Blip Stats** for $2.99.

[![Download on the Mac App Store](https://toolbox.marketingtools.apple.com/api/badges/download-on-the-mac-app-store/black/en-us)](https://apps.apple.com/us/app/blip-stats/id6762329495)

Some advanced features (fan speeds, temperatures, GPU utilization, disk I/O, top processes) require the free [Blip Helper](https://github.com/blaineam/blip/releases/latest/download/BlipHelper.dmg) companion app.

### Homebrew (Recommended for Direct Download)

```bash
brew install --cask blaineam/tap/blip
```

### Download DMG

Grab the latest notarized [**Blip.dmg**](https://github.com/blaineam/blip/releases/latest/download/Blip.dmg) (or [**BlipHelper.dmg**](https://github.com/blaineam/blip/releases/latest/download/BlipHelper.dmg) for the companion helper). Open it, drag to Applications, done.

### Build from Source

```bash
# Prerequisites
brew install xcodegen

# Clone and build
git clone https://github.com/blaineam/blip.git
cd blip
xcodegen generate
xcodebuild -scheme Blip -configuration Release -arch arm64
```

The app lands in `.build/DerivedData/Build/Products/Release/Blip.app`.

### Build DMG Locally

```bash
chmod +x Scripts/build-dmg.sh
./Scripts/build-dmg.sh              # full build + notarize
./Scripts/build-dmg.sh --skip-notarize  # unsigned local build
```

## 🔧 How It Works

```
+-----------------------------------------------------------+
|                   Menu Bar (NSStatusItem)                  |
|   [CPU]  [MEM]  [HD]  *                                   |
+----------------------------+------------------------------+
                             | click
                  +----------v-----------+
                  |  Popover             |  hover  +--------+
                  |   CPU     45%     >  | ------> | Detail |
                  |   Memory  67%     >  |         | Panel  |
                  |   Disk    34%     >  |         +--------+
                  |   Network  v^     >  |         | Cores  |
                  |   GPU     12%     >  |         | Loads  |
                  |   Battery 89%     >  |         | Procs  |
                  |                      |         | Charts |
                  |  MacBook Pro (M4)    |         +--------+
                  |  Up 3d 2h | Nominal  |
                  |  Blip v1.4.2         |
                  +----------------------+
```

## 🗂 Project Structure

```
Blip/
├── Blip/
│   ├── Sources/
│   │   ├── App/BlipApp.swift            # Entry point, NSStatusItem, popover
│   │   ├── Models/
│   │   │   ├── SystemStats.swift        # All data models
│   │   │   └── HistoryBuffer.swift      # Ring buffer for charts
│   │   ├── Services/
│   │   │   ├── SystemMonitor.swift      # Async coordinator
│   │   │   ├── CPUMonitor.swift         # host_processor_info
│   │   │   ├── MemoryMonitor.swift      # host_statistics64
│   │   │   ├── DiskMonitor.swift        # Volume stats + IOKit I/O
│   │   │   ├── GPUMonitor.swift         # IOAccelerator + Metal
│   │   │   ├── NetworkMonitor.swift     # NWPathMonitor + getifaddrs
│   │   │   ├── BatteryMonitor.swift     # IOPSCopyPowerSourcesInfo
│   │   │   ├── FanMonitor.swift         # SMC fan keys
│   │   │   ├── ProcessMonitor.swift     # proc_pidinfo + proc_pid_rusage
│   │   │   └── SMCKit.swift             # IOKit SMC interface
│   │   └── Views/
│   │       ├── StatusItemView.swift     # Menu bar layout (stacked/horizontal)
│   │       ├── PopoverView.swift        # Main overview + detail routing
│   │       ├── SettingsView.swift       # Preferences window
│   │       ├── Panels/                  # Detail panels per category
│   │       └── Components/              # Charts, bars, process rows
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── Blip.entitlements
├── Scripts/
│   ├── build-dmg.sh                     # Local build + package
│   └── generate-assets.swift            # App icon generator
├── .github/workflows/
│   ├── ci.yml                           # PR build + QA checks
│   └── release.yml                      # Tag → build → notarize → release
├── docs/                                # GitHub Pages site
├── project.yml                          # XcodeGen project definition
├── CHANGELOG.md
└── LICENSE                              # MIT
```

## 🤝 Contributing

1. Fork and clone the repo
2. `brew install xcodegen && xcodegen generate`
3. Open `Blip.xcodeproj` in Xcode or build from the command line
4. Make your changes, test on Apple Silicon hardware
5. Open a PR

### Guidelines

- Keep it tiny — no external dependencies
- Match the existing code style (SwiftUI, async/await, value types)
- Test on actual hardware — simulators can't read SMC or IOKit sensors
- Open an issue first for large changes

## 🖥 Requirements

- **macOS 14.0** (Sonoma) or later
- **Apple Silicon** (M1, M2, M3, M4, or newer)
- Xcode 16+ and XcodeGen (for building from source)

## ❓ FAQ

<details>
<summary><strong>Does Blip work on Intel Macs?</strong></summary>
<br>
No. Blip targets Apple Silicon exclusively. It uses ARM64-specific page sizes and Apple Silicon IOKit interfaces for GPU and thermal monitoring.
</details>

<details>
<summary><strong>Why does it need to run unsandboxed?</strong></summary>
<br>
Blip reads hardware sensors (SMC for fans, IOKit for GPU/disk I/O, process list for top apps) which require unsandboxed access. The app is fully open source — you can audit every line, and every release is notarized by Apple.
</details>

<details>
<summary><strong>How much memory does Blip use?</strong></summary>
<br>
Typically around 42 MB physical footprint. Blip shows its own memory usage in the popover footer so you can always verify.
</details>

<details>
<summary><strong>Why does the App Store version cost $2.99?</strong></summary>
<br>
The direct download and Homebrew versions are free and always will be. The $2.99 App Store price helps cover Apple Developer Program costs and supports ongoing development and maintenance. If you'd rather not pay, grab the identical free version from GitHub Releases or Homebrew.
</details>

## 📄 License

MIT — free as in beer and free as in freedom. See [LICENSE](LICENSE) for details.

---

Built by [Blaine Miller](https://github.com/blaineam). If Blip saves you from installing a 200 MB monitoring suite, consider starring the repo.
