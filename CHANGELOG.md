# Changelog

## v1.4.0

### Mac App Store
- **App Store release** — Blip is now available on the Mac App Store as "Blip Stats" ($2.99)
- **Sandboxed gracefully** — features that require hardware-level access (disk I/O, GPU utilization, fan speeds, temperatures, top processes) are hidden cleanly when the optional Blip Helper isn't installed, instead of showing zeroed-out data
- **Model name resolution** — built-in lookup table translates hardware identifiers (e.g. Mac16,8) to marketing names (MacBook Pro 14" M4 Pro) without needing system_profiler
- **Memory footprint** — App Store build now reports Blip's own memory usage using public Mach API (task_info) instead of showing 0 MB
- **Export compliance** — ITSAppUsesNonExemptEncryption set to skip the encryption dialog on every upload

### BlipHelper
- **Converted to proper .app** — BlipHelper is now a macOS app you drag to Applications and launch, instead of a CLI tool requiring manual LaunchAgent setup
- **Auto login item** — registers itself as a login item via SMAppService on first launch
- **Runs invisibly** — no menu bar icon; runs as a background daemon
- **Distinct icon** — BlipHelper has its own app icon (gold lightning bolt) to differentiate from the main Blip app

### Privacy
- **MAC address** — now hidden behind a "Tap to reveal" button, matching the WAN IP pattern
- **VPN IP** — also hidden behind "Tap to reveal" for privacy

### Settings
- **Website link** — settings now links to blip.wemiller.com
- **Helper download link** — App Store build includes a direct link to download Blip Helper from GitHub Releases

### CI/CD
- **DMG pre-releases** — PR pre-release builds now package as DMGs instead of zips, consistent with the release pipeline
- **Reliable DMG packaging** — fixed detach failures on volumes with spaces in the name by using device-path-based unmounting
- **Signed & notarized PR builds** — PR pre-release DMGs are now code-signed with Developer ID and notarized, so testers can install without Gatekeeper bypass

## v1.3.0

### Memory Optimization
- **Icon cache overhaul** — process icons now cached as PNG `Data` directly, eliminating redundant tiff-to-bitmap-to-PNG re-encoding on every cache hit (was running 10+ conversions per poll cycle)
- **Smaller icons** — process icons rendered at 16x16 instead of 32x32, reducing per-icon memory by 4x
- **Tighter cache limits** — icon cache reduced from 20 items / 5 MB to 10 items / 2 MB
- **Subprocess elimination** — `netstat` gateway lookup now cached and refreshed every ~30 seconds instead of spawning a new process every 2 seconds
- **GPU metadata caching** — GPU name and core count fetched once at init instead of re-querying sysctl and IOKit every poll cycle
- **Stable SwiftUI identity** — `VolumeInfo` uses `mountPoint` as its stable `Identifiable` id instead of allocating a new `UUID` every poll, reducing allocation churn and improving SwiftUI diffing
- **Process buffer reduction** — process name path buffer reduced from 4x `MAXPATHLEN` to 1x, saving ~3 KB per process per poll

### Result
- **Physical footprint** — reduced from ~250 MB to ~42 MB steady-state (measured via macOS `footprint` tool)
- **Per-poll allocations** — significantly reduced through caching, buffer reuse, and subprocess elimination

---

## v1.2.0

### Accuracy Improvements
- **Process memory** — now uses `phys_footprint` (via `proc_pid_rusage`) matching Activity Monitor exactly, instead of RSS from `ps`
- **Process CPU** — delta-based CPU calculation using `proc_pidinfo(PROC_PIDTASKINFO)` with proper Mach timebase conversion for accurate instantaneous usage instead of lifetime averages from `ps`
- **System processes** — system/root-owned processes (WindowServer, etc.) now appear in top process lists via `ps` fallback
- **Memory pressure** — uses kernel pressure level (`kern.memorystatus_vm_pressure_level`) with Normal/Warning/Critical indicators
- **Memory breakdown** — matches Activity Monitor exactly: App Memory = internal - purgeable, Used = App + Wired + Compressed
- **Battery health** — uses `NominalChargeCapacity` matching the Settings app; added battery condition (Normal/Service)

### New Data
- **Swap usage** — swap used/total shown in memory detail panel with progress bar
- **CPU idle %** — idle percentage displayed alongside user and system in CPU detail panel
- **Disk totals** — total data read and written since boot shown in disk detail panel
- **Network totals** — total bytes downloaded and uploaded since boot shown in network detail panel
- **Multi-interface** — all active network interfaces (Wi-Fi, Ethernet, etc.) listed with IPs and MACs when multiple are connected

### Charts
- **Y-axis labels** — bandwidth and disk I/O charts now show auto-scaled speed units (B/s, KB/s, MB/s, GB/s) on the Y-axis

### Settings
- **Colorize utilization toggle** — option to disable orange/red bar color changes at high CPU/memory/disk utilization
- **Default layout** — changed default menu bar layout from stacked to horizontal

### Live Refresh
- **Detail panel updates** — sub panels now live-refresh data as it changes instead of only updating on hover

### Polish
- **OG poster** — improved background with diagonal gradient and cyan radial glow

---

## v1.1.0

### Network Enhancements
- **Ping latency** — WAN ping and router ping displayed in network detail panel with color-coded thresholds
- **Configurable ping target** — set your preferred WAN ping address in Settings (default: 1.1.1.1)
- **Router IP** — default gateway IP shown in network detail, click to copy
- **MAC address** — NIC MAC address shown for active interfaces
- **WAN IP reveal** — tap-to-reveal button fetches your public IP on demand

### Thermal & Fans
- **CPU/GPU temperatures** — read via SMC and displayed in the thermal detail panel
- **Improved SMC compatibility** — support for AppleSMCKeysEndpoint on M4 and newer Apple Silicon

### UI Polish
- **Row alignment** — Network and Thermal overview rows now align with all other measurement rows
- **Chart rendering** — switched to monotone interpolation and explicit series differentiation for multi-line charts (disk I/O, network bandwidth)
- **Per-core grid** — CPU core bars use adaptive grid layout for machines with many cores
- **Process names** — full app names via NSRunningApplication and proc_name() instead of truncated ps output
- **Battery health** — fixed incorrect 2% reading by using AppleRawMaxCapacity
- **Detail panel corners** — removed shadow artifacts at rounded corners
- **Mac model name** — shows marketing name (e.g. "MacBook Pro (Apple M4 Pro)") via system_profiler

### Assets
- **App icon** — custom icon with colored bars and glowing blip dot
- **Web assets** — favicon, Apple touch icon, OG poster for GitHub Pages site

### Settings
- **Wider settings window** — prevents text wrapping in menu bar layout options
- **Ping target field** — configurable WAN ping destination address

---

## v1.0.0

Initial release of Blip — a featherlight macOS menu bar system monitor.

### Monitoring
- **CPU** — total usage, per-core bars, user/system breakdown, load averages (1m/5m/15m), P-core and E-core counts, top 5 processes by CPU with app icons
- **Memory** — usage percentage, total memory, active/wired/compressed/app breakdown, memory pressure indicator, top 5 processes by memory with app icons
- **Disk** — all mounted volumes with used/free space, real-time read/write speeds via IOKit, I/O history chart
- **GPU** — Apple Silicon GPU utilization via IOAccelerator, renderer name, GPU core count, historical usage chart
- **Network** — live connectivity dot in menu bar, upload/download speeds in overview and detail, IPv4/IPv6 addresses, LAN IP, VPN detection (Tailscale, WireGuard, utun), bandwidth history chart with separate up/down lines, click-to-copy addresses
- **Battery** — charge level, health %, cycle count, temperature, time remaining, charging status, power source
- **Fans** — RPM per fan with min/max range bars via SMC (shows "fanless Mac" on MacBook Air)
- **System info** — Mac model, macOS version, uptime, thermal state, Blip's own memory footprint

### UI
- **Menu bar layouts** — stacked (compact vertical bars) and horizontal (wide side-by-side) modes
- **Hover detail panels** — hover any overview row to reveal a detailed sub-panel with charts, breakdowns, and process lists
- **Pill-shaped bars** — rounded progress bars throughout the UI
- **Separate label controls** — independent toggles for measurement labels (CPU/MEM/HD) and value labels (percentages)
- **Customizable colors** — category colors (blue/green/orange), monochrome (matches menu bar), or custom color via picker
- **Historical charts** — CPU, memory, GPU sparklines; disk I/O and network bandwidth charts with proper series differentiation
- **Launch at login** — one toggle in settings via ServiceManagement

### Technical
- **Featherlight** — ~2 MB app bundle, zero external dependencies, 2-second polling with ring buffers
- **Efficient** — process icons only fetched for top 5 visible, NSHostingView reused for detail panels
- **Swift 6** — strict concurrency throughout, async/await, Sendable types
- **Apple Silicon only** — ARM64 targeting macOS 14.0+

### Distribution
- **CI/CD** — GitHub Actions pipeline with build, QA checks (binary size, architecture, security scan), notarization, and automated releases
- **DMG packaging** — signed and notarized disk images
- **Homebrew** — available via `brew install --cask blaineam/tap/blip`
- **GitHub Pages** — glassmorphic landing page with animated demo, feature grid, and FAQ
