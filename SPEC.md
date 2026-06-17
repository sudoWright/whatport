# WhatPort Specification

## Overview

A macOS menu bar utility that shows what every USB-C port is doing in real time:
which ports are active, what protocol, what speed, what power.

Bundle ID: `app.whatport.whatport`
Minimum deployment: macOS 14.0 (Sonoma)
Architecture: Apple Silicon only (M1+). Intel Macs use different IOKit classes
and are out of scope for v1.

---

## Architecture

Three layers. Each depends only on the one below it.

```
+------------------------------------------+
|  SwiftUI Layer (WhatPortUI)              |
|  Menu bar app, dropdown, expanded views  |
+------------------------------------------+
            |
            | observes published state
            v
+------------------------------------------+
|  Domain Layer (WhatPortCore)             |
|  Data model, port correlation, logic     |
+------------------------------------------+
            |
            | protocol-based data feed
            v
+------------------------------------------+
|  IOKit Layer (WhatPortIOKit)             |
|  All C API calls, notifications, polling |
+------------------------------------------+
```

### IOKit Layer (WhatPortIOKit)

Owns all interaction with IOKit C APIs. Nothing above this layer touches
`io_service_t`, `IORegistryEntry`, `CFMutableDictionary`, or any C pointer type.

Responsibilities:
- Service matching and iteration
- Reading registry properties (typed wrappers around `IORegistryEntryCreateCFProperty`)
- Registering and dispatching interest notifications
- Running a poll timer for power data
- Converting raw CF types into Swift value types before handing data up

Exposes a single protocol:

```swift
protocol PortDataSource: Sendable {
    func observePortUpdates() -> AsyncStream<PortSnapshot>
    func start() async
    func stop()
}
```

`PortSnapshot` is a complete, immutable snapshot of all port state at a point in
time. The IOKit layer produces a new snapshot whenever:
- A notification fires (connection event), or
- The power poll timer ticks (every 3 seconds)

This means the domain layer never needs to know *why* it got new data. It just
processes each snapshot.

### Domain Layer (WhatPortCore)

Pure Swift. No IOKit imports, no AppKit/SwiftUI imports. Testable in isolation.

Responsibilities:
- Correlating PhyID with Socket ID to build a coherent per-port picture
- Mapping raw IOKit values to meaningful enums (transport mode, link speed, etc.)
- Deciding which ports are "user-facing USB-C" vs internal/HDMI
- Holding the rolling power sample buffer for graphs
- Exposing an `@Observable` (or `ObservableObject`) model that the UI binds to

### SwiftUI Layer (WhatPortUI)

The menu bar app, dropdown content, and expanded port views.

Responsibilities:
- Rendering the menu bar icon + badge
- Showing the port list dropdown
- Showing the expanded detail view per port
- Formatting values for display (e.g., "5.9W", "40 Gbps x 2")

No data fetching, no IOKit, no business logic.

---

## Data Model

### PortState (one per USB-C port)

```swift
struct PortState: Identifiable {
    let id: Int                      // physical port number (1-based, from Socket ID)
    let physicalPosition: PortPosition  // left-rear, left-front, right, etc.

    // Lane allocation (from AppleT8132TypeCPhy)
    var lane0: LaneState
    var lane1: LaneState
    var usb2Active: Bool

    // Thunderbolt link (from IOThunderboltPort, nil if not in TB mode)
    var thunderboltLink: ThunderboltLinkState?

    // Power (from PowerOutDetails, nil if not metered)
    var power: PortPower?

    // Connected device name (best available from TB DROM, SOP product string, or DP ProductName)
    var deviceName: String?

    // Derived convenience
    var isActive: Bool               // any lane has a transport
    var primaryProtocol: Protocol    // .thunderbolt, .displayPort, .usbOnly, .idle
}
```

### LaneState

```swift
struct LaneState {
    var transport: LaneTransport     // .thunderbolt, .displayPort, .idle
    var powerLevel: PowerLevel       // .on, .off
    var client: String?              // driver name, e.g. "AppleThunderboltNHIType7"
}

enum LaneTransport {
    case thunderbolt    // CIO tunnel (Thunderbolt / USB4)
    case displayPort    // DP alt-mode (native, not tunneled)
    case idle           // nothing using this lane
}
```

### ThunderboltLinkState

```swift
struct ThunderboltLinkState {
    var generation: TBGeneration     // .tb3, .tb4, .tb5
    var perLaneGbps: Int             // 10, 20, or 40
    var txLanes: Int                 // 1, 2, or 3
    var rxLanes: Int                 // 1, 2, or 3
    var totalGbps: Int               // perLaneGbps * txLanes (e.g. 80 for dual-lane TB4)
    var deviceName: String?          // from DROM if available
    var deviceVendor: String?
}

enum TBGeneration {
    case tb3    // speed code 0x8, 10 Gbps/lane
    case tb4    // speed code 0x4, 20 Gbps/lane (also covers USB4 Gen3)
    case tb5    // speed code 0x2, 40 Gbps/lane
}
```

### PortPower

```swift
struct PortPower {
    var watts: Double                // actual measured output (from Watts field, in centiwatts -> convert)
    var current: Int                 // mA
    var voltage: Int                 // mV (actual measured, AdapterVoltage)
    var configuredVoltage: Int       // mV (PD negotiated)
    var configuredCurrent: Int       // mA (PD negotiated max)
    var vconnCurrent: Int            // mA (cable electronics draw)
}
```

### DisplayPortState (for expanded view)

```swift
struct DisplayPortState {
    var monitorName: String?
    var manufacturer: String?
    var laneCount: Int               // active DP lanes (2 or 4)
    var maxLaneCount: Int
    var linkRate: String             // "HBR2 (5.4 Gbps/lane)" etc.
    var tunneled: Bool               // true = running over TB tunnel
    var pixelClock: String?          // from AppleTypeCPhyDisplayPortPclk
}
```

---

## Refresh Strategy

Hybrid: notifications for state changes, polling for power.

### Why not pure notifications?

Probe 30 confirmed: power data (PowerOutDetails) updates every 2-5 seconds but
fires NO notification. You must poll. Connection/disconnection events do fire
notifications (113 per plug cycle), so those are event-driven.

### Why not pure polling?

Polling everything at 3s means a 0-3 second lag on plug/unplug detection. Users
expect instant feedback when they plug something in. Notifications give sub-second
response for state changes.

### The hybrid approach

```
Connection state change?
  -> Notification fires (instant, from IOPortTransportStateCC)
  -> Read PHY lanes, TB link, device name ONCE
  -> Publish updated PortSnapshot immediately

Power data needed?
  -> 3-second poll timer on AppleSmartBattery.PowerOutDetails
  -> Only active while at least one port is sourcing power
  -> Stop timer when all ports idle (save energy)

Display connected?
  -> Read DP properties once after notification
  -> Only re-read if new notification fires
```

### Lifecycle

1. App launches. IOKit layer matches all relevant services, reads initial state,
   produces first snapshot.
2. IOKit layer registers interest notifications on `IOPortTransportStateCC`.
3. If any port is sourcing power, start the 3-second poll timer.
4. On notification: re-read PHY + TB state, produce new snapshot.
5. On poll tick: re-read PowerOutDetails only, produce new snapshot.
6. If all ports go idle and no power sourcing: stop poll timer.

### Performance

- Idle (nothing connected): zero CPU. No polling, just waiting for notifications.
- Active (devices connected, no power): near-zero. Only fires on state changes.
- Active with power: one IOKit property read every 3 seconds. Negligible.

---

## Menu Bar UX

### Icon

SF Symbol `cable.connector` (or custom if needed). Small, monochrome, fits the
system menu bar style.

### Badge

Text next to the icon showing active port count: "2/3" means 2 of 3 USB-C ports
are in use. Updates instantly on plug/unplug.

The denominator is the total number of user-facing USB-C ports on this machine
(discovered at launch by counting PHY instances that map to real ports).

### Dropdown (click the icon)

A list of all USB-C ports, one row each. Each row shows:

```
[Port icon]  Port 1: TB4 dual-lane, 40 Gbps, 5.9W out
[Port icon]  Port 2: DP alt-mode, HBR2, 2 lanes
[Port icon]  Port 3: idle
```

Idle ports are dimmed. Active ports use the standard text colour.

The port icon could use colour to indicate mode:
- Blue/purple: Thunderbolt/USB4
- Orange: DisplayPort
- Green: USB-only
- Grey: idle

Footer of the dropdown:
- "Quit WhatPort" menu item
- Settings gear icon (opens preferences)

### Behaviour

- Left-click on the menu bar icon: opens the dropdown.
- Click a port row: expands to the detail view (see below).
- The dropdown is a standard NSPopover or NSMenu. Keep it lightweight.

---

## Expanded Port View

When you click a port row in the dropdown, it expands (or opens a detail popover)
showing:

### Lane Diagram

A visual representation of what each lane is doing:

```
Lane 0: [====CIO====]  40 Gbps
Lane 1: [====CIO====]  40 Gbps
USB2:   [===active===]
```

Or for DP alt-mode:

```
Lane 0: [=DisplayPort=]  HBR2
Lane 1: [=DisplayPort=]  HBR2
USB2:   [===active===]
```

Or mixed (2-lane DP + USB3, though rare on modern Macs):

```
Lane 0: [=DisplayPort=]  HBR2
Lane 1: [====USB3====]   10 Gbps
USB2:   [===active===]
```

Colour-coded by transport type. Simple rectangles, not fancy graphics.

### Power Section (if power data available)

```
Power:  5.9W (113 mA @ 5.2V actual)
        Contract: 5V / 1.5A (7.5W max)
        VConn: 14 mA (cable electronics)
```

If PowerOutDetails is unavailable for this port (desktop Mac, or older generation):
show "Power metering not available on this hardware" in muted text.

### Power Graph (if power data available)

A small sparkline of watts over the last ~60 seconds. Built with SwiftUI `Chart`
and `LineMark`. Only renders while power data is flowing.

### Connected Device

```
Connected: CalDigit TS5 Plus
           via Thunderbolt 5, asymmetric 3+1
```

Device name from the best available source (TB DROM, SOP product string, DP
monitor name).

---

## Error and Edge Cases

### No ports active

All rows show "idle" with dimmed text. Badge shows "0/3". No poll timer running.
Minimal resource usage.

### Permissions

All IOKit reads used by WhatPort are unprivileged. No special entitlements needed.
No App Sandbox exceptions needed for IOKit registry reads. App Store safe.

If a future macOS release restricts access: show a clear message explaining what
happened and link to the app's support page. Don't crash.

### Desktop Macs (Mac Studio, Mac mini, Mac Pro)

- PHY lane data: should work (same `AppleTypeCPhy` class, untested on desktops but
  the class is chip-level, not form-factor-level).
- TB link data: works (confirmed on M3 Ultra Mac Studio).
- Power data (PowerOutDetails): NOT available on desktops. The power section in
  the expanded view should show "Power metering unavailable on desktop Macs" and
  hide the graph.
- Port count may differ (Mac Studio has more USB-C ports than a MacBook).

### M-series vs Intel

Intel Macs are out of scope for v1. If the app launches on an Intel Mac:
show a single-screen message explaining the app requires Apple Silicon.
Detection: check for `AppleT*TypeCPhy` service existence at launch.

### Older M-series (M1)

M1 uses the same IOKit class hierarchy but may have fewer PHY instances (2 ports
on MacBook Air vs 3-4 on Pro). The app should dynamically discover port count,
never hardcode it.

PowerOutDetails is confirmed absent on M1 Max (firmware-dependent). Show the
"not available" fallback for power.

### PhyID-to-port mapping uncertainty

The probe shows PhyID 0-3 but the mapping to physical port number needs runtime
correlation. Strategy:

1. At launch, enumerate all `AppleTypeCPhy` instances (get PhyID for each).
2. Enumerate all `IOThunderboltPort` instances where Description = "Thunderbolt Port"
   (get Socket ID for each).
3. Cross-reference: the TB port's Socket ID = the physical port number. The PHY's
   index in the ATC (Apple Type-C) controller tree should map to the same port.
4. If correlation fails, fall back to displaying PhyID as the port number (better
   than nothing).

The correlation logic lives in the domain layer. If we can't establish a reliable
mapping on a given machine, log a warning and show ports by PhyID.

### HDMI / MagSafe filtering

- The built-in HDMI port likely does NOT appear as a TypeCPhy instance (TBD,
  verify on first build). If the 4th PHY is the HDMI port, filter it out.
- MagSafe uses `AppleHPMInterfaceType11`, not Type10, and has no PHY lane entry.
  It won't show up in the port list.
- Only user-facing USB-C ports should appear. Filter any non-USB-C PHY instances.

### Hot-plug during expanded view

If the user has a port's detail view open and the device disconnects:
- Immediately update the lane diagram to show "idle"
- Clear the device name
- Keep the power graph showing historical data (greyed out) with a "disconnected"
  label
- Don't close the expanded view automatically (jarring UX)

### System sleep/wake

On wake, the IOKit notification system fires events as ports re-enumerate.
The app should treat wake as a "re-read everything" trigger. Register for
`NSWorkspace.didWakeNotification` and force a full snapshot refresh.

---

## Out of Scope for v1

- Cable quality / resistance estimation (complex, unvalidated accuracy)
- Charger PDO ladder display (belongs in a separate "Charger Tester" app)
- Port health counters (lifetime attach/detach, hard resets)
- USB device tree enumeration (which USB devices are behind a hub)
- Intel Mac support
- iOS/iPadOS (no IOKit access)
- Preferences beyond "Launch at Login" and "Show in Dock" toggle

---

## Decisions

1. **Port position labels.** Numbered only ("Port 1", "Port 2", "Port 3").
   No position lookup table. Simpler, works on all machines without maintenance.

2. **Asymmetric TB5 display.** Show all lanes with direction arrows (e.g.
   3 TX lanes + 1 RX lane rendered separately with arrows indicating direction).
   Label as "120/40 Gbps asymmetric" in the summary line.

3. **Multiple displays on one port.** Show both DP streams individually in the
   expanded view. Each stream gets its own row with monitor name and link rate.

4. **Settings window.** Minimal: "Launch at Login" toggle only. Hardcode the
   3-second poll interval. No "Show in Dock" toggle (menu bar apps are
   LSUIElement by default).
