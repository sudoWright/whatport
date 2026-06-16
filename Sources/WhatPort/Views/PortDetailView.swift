import SwiftUI
import Charts
import WhatPortCore

struct PortDetailView: View {
    let port: PortState
    let powerHistory: [PowerSample]
    let powerMeteringAvailable: Bool
    var isCharging: Bool = false
    var fullyCharged: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                portHeader
                cardContent
            }
            .padding(16)
        }
    }

    private var chartTint: Color { .blue }

    // MARK: - Port Identity Header

    private var portHeader: some View {
        HStack(alignment: .center) {
            Text(portName)
                .font(.title3.weight(.semibold))
            Spacer()
            protocolChip
        }
    }

    private var portName: String {
        switch port.portType {
        case .magSafe: return "MagSafe"
        case .usbC: return "Port \(port.id)"
        }
    }

    private var protocolChip: some View {
        let (label, color) = protocolChipInfo
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var protocolChipInfo: (String, Color) {
        switch port.primaryProtocol {
        case .thunderbolt: return ("Thunderbolt", .blue)
        case .displayPort:  return ("DisplayPort", .orange)
        case .usbOnly:      return ("USB", .green)
        case .charging:     return ("Charging", .yellow)
        case .idle:         return ("Idle", .gray)
        }
    }

    // MARK: - Card Container

    // Small-caps style section header: recedes so the values lead the eye.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - Card Content (protocol-specific ordering)

    @ViewBuilder
    private var cardContent: some View {
        switch port.primaryProtocol {
        case .charging:
            sectionCard { powerSection }
            if !powerHistory.isEmpty {
                sectionCard { powerChart }
            }
            if port.portType != .magSafe {
                sectionCard { laneInfoSection }
                if let cap = port.thunderboltCapability {
                    sectionCard { thunderboltSection(capability: cap, link: port.thunderboltLink) }
                }
                if let cable = port.cable {
                    sectionCard { cableSection(cable) }
                }
            }

        case .usbOnly:
            if let device = port.usbDevice {
                sectionCard {
                    deviceSection(device)
                    displayResolutionRow
                }
            }
            sectionCard { laneInfoSection }
            if let cap = port.thunderboltCapability {
                sectionCard { thunderboltSection(capability: cap, link: port.thunderboltLink) }
            }
            if let cable = port.cable {
                sectionCard { cableSection(cable) }
            }
            sectionCard { powerSection }
            if !powerHistory.isEmpty {
                sectionCard { powerChart }
            }

        case .thunderbolt:
            if let device = port.usbDevice {
                sectionCard {
                    deviceSection(device)
                    displayResolutionRow
                }
            } else if port.displayWidth > 0 && port.displayHeight > 0 {
                // Display with no USB device (e.g. a pure DP monitor): the
                // resolution still gets a card rather than floating loose.
                sectionCard { displayResolutionRow }
            }
            if let cap = port.thunderboltCapability {
                sectionCard { thunderboltSection(capability: cap, link: port.thunderboltLink) }
            }
            sectionCard { laneInfoSection }
            if let cable = port.cable {
                sectionCard { cableSection(cable) }
            }
            sectionCard { powerSection }
            if !powerHistory.isEmpty {
                sectionCard { powerChart }
            }

        case .displayPort:
            if let device = port.usbDevice {
                sectionCard {
                    deviceSection(device)
                    displayResolutionRow
                }
            } else if port.displayWidth > 0 && port.displayHeight > 0 {
                sectionCard { displayResolutionRow }
            }
            sectionCard { laneInfoSection }
            if let cap = port.thunderboltCapability {
                sectionCard { thunderboltSection(capability: cap, link: port.thunderboltLink) }
            }
            if let cable = port.cable {
                sectionCard { cableSection(cable) }
            }
            sectionCard { powerSection }
            if !powerHistory.isEmpty {
                sectionCard { powerChart }
            }

        case .idle:
            sectionCard { laneInfoSection }
            if let cap = port.thunderboltCapability {
                sectionCard { thunderboltSection(capability: cap, link: port.thunderboltLink) }
            }
            sectionCard { powerSection }
            if !powerHistory.isEmpty {
                sectionCard { powerChart }
            }
        }
    }

    // MARK: - Device

    private func deviceSection(_ device: USBDeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Device")

            HStack {
                Text(device.productName)
                    .font(.body.weight(.medium))
                Spacer()
                if !device.vendorName.isEmpty {
                    Text(device.vendorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if let speed = device.speed {
                    LabeledValue(label: "Speed", value: speed.label)
                }
                if !device.usbVersion.isEmpty {
                    LabeledValue(label: "Version", value: device.usbVersion)
                }
                if device.currentDraw > 0 {
                    LabeledValue(label: "Power Draw", value: "\(device.currentDraw) mA")
                }
            }

            if let serial = device.serialNumber {
                HStack {
                    Text("Serial")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Text(serial)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - Display Resolution

    @ViewBuilder
    private var displayResolutionRow: some View {
        if port.displayWidth > 0 && port.displayHeight > 0 {
            LabeledValue(
                label: "Native Resolution",
                value: "\(port.displayWidth) x \(port.displayHeight)"
            )
        }
    }

    // MARK: - Lanes + Stats (combined)

    private var laneInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Link activity")
            LaneBar(
                label: "Lane 0",
                state: port.lane0,
                tbLink: port.thunderboltLink,
                liveTransports: port.liveTransports,
                dpLinkRate: port.dpLinkRate
            )
            LaneBar(
                label: "Lane 1",
                state: port.lane1,
                tbLink: port.thunderboltLink,
                liveTransports: port.liveTransports,
                dpLinkRate: port.dpLinkRate
            )
            USB2Bar(active: port.usb2Active)

            if let stats = port.portStats {
                statsLine(stats)
                    .padding(.top, 2)
            }

            if let health = port.health {
                healthRow(health)
                    .padding(.top, 2)
            }
        }
    }

    private func statsLine(_ stats: PortStatistics) -> some View {
        let errorCount = stats.overcurrentCount + stats.linkErrorCount
            + stats.enumerationFailureCount + stats.addressFailureCount

        return HStack(spacing: 4) {
            Text("Lifetime:")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text("\(stats.connectCount) connections")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\u{00B7}")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text(errorSummary(stats, total: errorCount))
                .font(.footnote)
                .foregroundColor(errorCount > 0 ? .orange : .gray)
        }
    }

    private func errorSummary(_ stats: PortStatistics, total: Int) -> String {
        if total == 0 { return "No errors" }
        var parts: [String] = []
        if stats.linkErrorCount > 0 {
            parts.append("\(stats.linkErrorCount) link")
        }
        if stats.overcurrentCount > 0 {
            parts.append("\(stats.overcurrentCount) overcurrent")
        }
        if stats.enumerationFailureCount > 0 {
            parts.append("\(stats.enumerationFailureCount) enum")
        }
        if stats.addressFailureCount > 0 {
            parts.append("\(stats.addressFailureCount) address")
        }
        return parts.joined(separator: ", ") + " error\(total > 1 ? "s" : "")"
    }

    private func healthRow(_ health: PortHealth) -> some View {
        HStack(spacing: 6) {
            Text("Port health:")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            healthBadge(health)
        }
    }

    @ViewBuilder
    private func healthBadge(_ health: PortHealth) -> some View {
        let (fill, textColor, label): (Color, Color, String) = {
            switch health.severity {
            case .ok:
                return (.green, .green, "OK")
            case .warning:
                let text = health.ldcmStatus.isEmpty ? "Warning" : health.ldcmStatus
                return (.orange, .orange, text)
            case .serious:
                let n = health.overcurrentCount
                let text = "Overcurrent: \(n) event\(n > 1 ? "s" : "")"
                return (.red, .red, text)
            }
        }()

        Text(label)
            .font(.footnote.weight(.medium))
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill.opacity(0.12), in: Capsule())
    }

    // MARK: - Power Section

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Power")

            if let power = port.power {
                HStack {
                    Text(WattsFormat.string(power.watts))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("(\(formatAmps(power.current)) at \(formatVolts(power.voltage)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    // The PD contract comes from PowerOutDetails. SMC-only ports
                    // (no battery controller) report it as 0, so hide the row
                    // rather than show a misleading "0 V / 0 mA".
                    if power.configuredVoltage > 0 || power.configuredCurrent > 0 {
                        LabeledValue(
                            label: "Contract",
                            value: "\(formatVolts(power.configuredVoltage)) / \(formatAmps(power.configuredCurrent))"
                        )
                    }
                    if power.vconnCurrent > 0 {
                        LabeledValue(
                            label: "VConn",
                            value: "\(power.vconnCurrent) mA"
                        )
                    }
                }
            } else if !powerMeteringAvailable {
                Text("Per-port power metering not reported on this Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not sourcing power")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Converts millivolts to a human-readable volts string, e.g. 5234 -> "5.2 V", 5000 -> "5 V".
    // The whole-number check runs on the FORMATTED value: 4960 mV formats to
    // "5.0", which must render as "5 V", not "5.0 V".
    private func formatVolts(_ millivolts: Int) -> String {
        let formatted = String(format: "%.1f", Double(millivolts) / 1000.0)
        if formatted.hasSuffix(".0") {
            return "\(formatted.dropLast(2)) V"
        }
        return "\(formatted) V"
    }

    // Converts milliamps to a human-readable current string.
    // Under 1000 mA: shows milliamps, e.g. 97 -> "97 mA", 500 -> "500 mA".
    // 1000 mA or more: shows amps with one decimal, dropping a trailing ".0"
    // from the formatted value, e.g. 1500 -> "1.5 A", 2960 -> "3 A".
    private func formatAmps(_ milliamps: Int) -> String {
        if milliamps < 1000 {
            return "\(milliamps) mA"
        }
        let formatted = String(format: "%.1f", Double(milliamps) / 1000.0)
        if formatted.hasSuffix(".0") {
            return "\(formatted.dropLast(2)) A"
        }
        return "\(formatted) A"
    }

    // MARK: - Power Chart

    private var powerChart: some View {
        // Compute scale values once so both .chartYScale and .chartYAxis use the same range.
        // Small range (<=2 W): keep one-decimal precision so 0.5-steps show.
        // Larger range: round ceiling up to the next even number so mid is
        // always a whole watt and integer labels are used.
        let maxSample = powerHistory.map(\.watts).max() ?? 0
        let rawCeil = max(1.0, ceil(maxSample))
        let ceiling: Double = rawCeil <= 2.0 ? rawCeil : (rawCeil.truncatingRemainder(dividingBy: 2) == 0 ? rawCeil : rawCeil + 1)
        let mid = ceiling / 2
        let fmt = ceiling <= 2.0 ? "%.1fW" : "%.0fW"

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Power (60s)")
            Chart(powerHistory.indices, id: \.self) { index in
                let sample = powerHistory[index]
                AreaMark(
                    x: .value("Time", index),
                    y: .value("Watts", sample.watts)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [
                            chartTint.opacity(port.isActive ? 0.25 : 0.05),
                            chartTint.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Time", index),
                    y: .value("Watts", sample.watts)
                )
                .foregroundStyle(chartTint.opacity(port.isActive ? 0.7 : 0.2))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...ceiling)
            .chartYAxis {
                // 3 ticks: 0, mid, ceiling -- all within the pinned 0...ceiling domain.
                AxisMarks(position: .leading, values: [0, mid, ceiling]) { value in
                    AxisValueLabel {
                        if let w = value.as(Double.self) {
                            Text(String(format: fmt, w))
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .frame(height: 40)
            .overlay {
                if !port.isActive && !powerHistory.isEmpty {
                    Text("disconnected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Thunderbolt

    private func thunderboltSection(
        capability: ThunderboltCapability,
        link: ThunderboltLinkState?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Thunderbolt")

            // Current negotiated link
            if let link {
                let lanes = formatLanes(tx: link.txLanes, rx: link.rxLanes)
                LabeledValue(
                    label: "Current link",
                    value: "\(link.generation.label), \(lanes), \(link.totalGbps) Gbps"
                )
            } else {
                LabeledValue(label: "Current link", value: "No active link")
            }

            // Port ceiling, regardless of what is currently connected
            let maxLanes = capability.maxLanes > 1 ? "dual-lane" : "single-lane"
            LabeledValue(
                label: "Port supports",
                value: "Up to \(capability.maxGeneration.label), \(maxLanes) (\(capability.maxGeneration.perLaneGbps) Gbps/lane)"
            )
        }
    }

    private func formatLanes(tx: Int, rx: Int) -> String {
        if tx == rx {
            return tx > 1 ? "dual-lane" : "single-lane"
        }
        return "\(tx)TX/\(rx)RX"
    }

    // MARK: - Cable

    private func cableSection(_ cable: CableInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Cable")
            HStack(spacing: 12) {
                LabeledValue(label: "Type", value: cable.productType)
                if cable.pdRevision > 0 {
                    LabeledValue(label: "PD Revision", value: "\(cable.pdRevision).0")
                }
            }
        }
    }

}

// MARK: - Lane Bar

struct LaneBar: View {
    let label: String
    let state: LaneState
    let tbLink: ThunderboltLinkState?
    var liveTransports: [LiveTransport] = []
    // PHY-derived DP link rate as fallback when no transport state available
    var dpLinkRate: String = ""

    // Live transport data matching this lane's protocol
    private var liveTransport: LiveTransport? {
        liveTransports.first { $0.kind == state.transport }
    }

    // Power level from the PHY updates in real-time as devices
    // sleep/wake. "on" = lane actively carrying data right now.
    private var isLanePowered: Bool {
        state.powerLevel == .on
    }

    // macOS Transport Restriction Mode has blocked data on this lane.
    // The link negotiated a speed but no data flows until the device is
    // authorised (System Settings > Privacy & Security > Allow accessories).
    private var isRestricted: Bool {
        liveTransport?.restricted ?? false
    }

    var body: some View {
        HStack(spacing: 6) {
            // Live power indicator: green dot when powered, dim when sleeping
            Circle()
                .fill(powerIndicatorColor)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)

            RoundedRectangle(cornerRadius: 5)
                .fill(barFill)
                .frame(height: 22)
                .overlay {
                    HStack(spacing: 4) {
                        if isRestricted {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(barTextColor)
                        }
                        Text(barLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(barTextColor)
                        if let lt = liveTransport, lt.tunneled {
                            Text("tunnel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(barTextColor.opacity(0.5))
                        }
                    }
                }
                .help(isRestricted
                    ? "Data blocked by macOS. Approve the device in System Settings > Privacy & Security > Allow accessories to connect."
                    : "")
        }
    }

    private var powerIndicatorColor: Color {
        guard state.transport != .idle else { return .clear }
        return isLanePowered ? .green : .gray.opacity(0.3)
    }

    // Muted tinted fill instead of solid color
    private var barFill: Color {
        // A blocked USB lane is a warning state -- amber fill, not healthy green.
        if isRestricted { return .orange.opacity(isLanePowered ? 0.12 : 0.06) }
        let opacity = isLanePowered ? 0.12 : 0.06
        switch state.transport {
        case .thunderbolt: return .blue.opacity(opacity)
        case .displayPort: return .orange.opacity(opacity)
        case .usb: return .green.opacity(opacity)
        case .idle: return Color.primary.opacity(0.04)
        }
    }

    // Colored text on muted background instead of white on solid
    private var barTextColor: Color {
        // A blocked lane is a warning state -- amber text matches the amber fill.
        if isRestricted { return .orange }
        switch state.transport {
        case .thunderbolt: return .blue
        case .displayPort: return .orange
        case .usb: return .green
        case .idle: return .clear
        }
    }

    private var barLabel: String {
        switch state.transport {
        case .thunderbolt:
            // Prefer live CIO transport data, fall back to TB link info
            if let lt = liveTransport, !lt.dataRate.isEmpty {
                return "CIO \u{00B7} \(lt.dataRate)"
            }
            if let tb = tbLink {
                return "CIO \u{00B7} \(tb.perLaneGbps) Gbps"
            }
            return "CIO"
        case .displayPort:
            // Prefer live DP transport data, fall back to PHY link rate
            if let lt = liveTransport, !lt.dataRate.isEmpty {
                return "DP \u{00B7} \(lt.dataRate)"
            }
            let rate = Self.formatDPLinkRate(dpLinkRate)
            if !rate.isEmpty {
                return "DP \u{00B7} \(rate)"
            }
            return "DisplayPort"
        case .usb:
            // A restricted link has no active data flow; IOKit reports "None"
            // as the data rate. Skip the rate entirely -- just label it blocked.
            if isRestricted {
                return "USB3 \u{00B7} Blocked"
            }
            // Prefer live USB3 transport data, fall back to device speed
            if let lt = liveTransport, !lt.dataRate.isEmpty {
                return "USB3 \u{00B7} \(lt.dataRate)"
            }
            return "USB3"
        case .idle:
            return ""
        }
    }

    // Parse PHY "5.40Gbps/lane (HBR2)" into "5.4 Gbps" (fallback only)
    static func formatDPLinkRate(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        guard let slashIdx = raw.firstIndex(of: "/") else { return raw }
        let prefix = String(raw[raw.startIndex..<slashIdx])
            .replacingOccurrences(of: "Gbps", with: "")
        if let value = Double(prefix) {
            if value == value.rounded() {
                return "\(Int(value)) Gbps"
            }
            return String(format: "%.1f Gbps", value)
        }
        return raw
    }
}

struct USB2Bar: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 6, height: 6)
            Text("USB2")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)

            RoundedRectangle(cornerRadius: 5)
                .fill(active ? Color.green.opacity(0.12) : Color.primary.opacity(0.04))
                .frame(height: 22)
                .overlay {
                    if active {
                        Text("480 Mbps")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
        }
    }
}

// MARK: - Helpers

struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}
