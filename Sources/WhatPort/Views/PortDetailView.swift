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
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                cardContent
            }
            .padding(16)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Circle()
                .fill(protocolColor)
                .frame(width: 10, height: 10)
            Text(headerTitle)
                .font(.headline)
            Spacer()
            Text(protocolLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headerTitle: String {
        if port.portType == .magSafe {
            return "MagSafe"
        }
        return "Port \(port.id)"
    }

    private var protocolColor: Color {
        switch port.primaryProtocol {
        case .thunderbolt: return .purple
        case .displayPort: return .orange
        case .usbOnly: return .green
        case .charging: return .yellow
        case .idle: return .gray.opacity(0.4)
        }
    }

    private var protocolLabel: String {
        switch port.primaryProtocol {
        case .thunderbolt:
            if let tb = port.thunderboltLink {
                return "\(tb.generation.label), \(tb.totalGbps) Gbps"
            }
            return "Thunderbolt"
        case .displayPort: return "DisplayPort"
        case .usbOnly: return "USB"
        case .charging:
            if fullyCharged { return "Battery Full" }
            if isCharging { return "Charging" }
            return "Charger Connected"
        case .idle: return "idle"
        }
    }

    // MARK: - Card Content (protocol-specific ordering)

    @ViewBuilder
    private var cardContent: some View {
        switch port.primaryProtocol {
        case .charging:
            powerSection
            if !powerHistory.isEmpty { powerChart }
            laneInfoSection
            if let cap = port.thunderboltCapability {
                thunderboltSection(capability: cap, link: port.thunderboltLink)
            }
            if let cable = port.cable { cableSection(cable) }

        case .usbOnly:
            if let device = port.usbDevice { deviceSection(device) }
            powerSection
            if !powerHistory.isEmpty { powerChart }
            laneInfoSection
            if let cap = port.thunderboltCapability {
                thunderboltSection(capability: cap, link: port.thunderboltLink)
            }
            if let cable = port.cable { cableSection(cable) }

        case .thunderbolt:
            if let device = port.usbDevice { deviceSection(device) }
            if let cap = port.thunderboltCapability {
                thunderboltSection(capability: cap, link: port.thunderboltLink)
            }
            laneInfoSection
            powerSection
            if !powerHistory.isEmpty { powerChart }
            if let cable = port.cable { cableSection(cable) }

        case .displayPort:
            if let device = port.usbDevice { deviceSection(device) }
            laneInfoSection
            powerSection
            if !powerHistory.isEmpty { powerChart }
            if let cap = port.thunderboltCapability {
                thunderboltSection(capability: cap, link: port.thunderboltLink)
            }
            if let cable = port.cable { cableSection(cable) }

        case .idle:
            laneInfoSection
            if let cap = port.thunderboltCapability {
                thunderboltSection(capability: cap, link: port.thunderboltLink)
            }
            powerSection
            if !powerHistory.isEmpty { powerChart }
        }
    }

    // MARK: - Device

    private func deviceSection(_ device: USBDeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Device")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

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
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(serial)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - Lanes + Stats (combined)

    private var laneInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lanes")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            LaneBar(
                label: "Lane 0",
                state: port.lane0,
                tbLink: port.thunderboltLink,
                usbSpeed: port.usbSpeed,
                dpLinkRate: port.dpLinkRate
            )
            LaneBar(
                label: "Lane 1",
                state: port.lane1,
                tbLink: port.thunderboltLink,
                usbSpeed: port.usbSpeed,
                dpLinkRate: port.dpLinkRate
            )
            USB2Bar(active: port.usb2Active)

            if let stats = port.portStats {
                statsLine(stats)
                    .padding(.top, 2)
            }
        }
    }

    private func statsLine(_ stats: PortStatistics) -> some View {
        let errorCount = stats.overcurrentCount + stats.linkErrorCount
            + stats.enumerationFailureCount + stats.addressFailureCount

        return HStack(spacing: 4) {
            Text("\(stats.connectCount) connections")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\u{00B7}")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(errorSummary(stats, total: errorCount))
                .font(.caption)
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

    // MARK: - Power Section

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Power")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            if let power = port.power {
                HStack {
                    Text(String(format: "%.1fW", power.watts))
                        .font(.system(.title3, design: .rounded, weight: .medium))
                    Text("(\(power.current) mA @ \(power.voltage) mV)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    LabeledValue(
                        label: "Contract",
                        value: "\(power.configuredVoltage)mV / \(power.configuredCurrent)mA"
                    )
                    if power.vconnCurrent > 0 {
                        LabeledValue(
                            label: "VConn",
                            value: "\(power.vconnCurrent) mA"
                        )
                    }
                }
            } else if !powerMeteringAvailable {
                Text("Power metering unavailable on this hardware")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Not sourcing power")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Power Chart

    private var powerChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(powerHistory.indices, id: \.self) { index in
                let sample = powerHistory[index]
                LineMark(
                    x: .value("Time", index),
                    y: .value("Watts", sample.watts)
                )
                .foregroundStyle(.purple.opacity(port.isActive ? 0.7 : 0.2))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let w = value.as(Double.self) {
                            Text(String(format: "%.0fW", w))
                                .font(.system(size: 11))
                        }
                    }
                }
            }
            .frame(height: 40)
            .overlay {
                if !port.isActive && !powerHistory.isEmpty {
                    Text("disconnected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
            Text("Thunderbolt")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            if let link {
                let lanes = formatLanes(tx: link.txLanes, rx: link.rxLanes)
                Text("\(link.generation.label) \(lanes), \(link.totalGbps) Gbps")
                    .font(.body.weight(.medium))
            } else {
                Text("No active link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                LabeledValue(
                    label: "Max Speed",
                    value: "\(capability.maxGeneration.label) (\(capability.maxGeneration.perLaneGbps) Gbps/lane)"
                )
                LabeledValue(
                    label: "Max Lanes",
                    value: capability.maxLanes > 1 ? "Dual-lane" : "Single-lane"
                )
            }
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
            Text("Cable")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
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
    var usbSpeed: USBSpeed?
    var dpLinkRate: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(barColor)
                .frame(height: 18)
                .overlay {
                    Text(barLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
        }
    }

    private var barColor: Color {
        switch state.transport {
        case .thunderbolt: return .purple
        case .displayPort: return .orange
        case .usb: return .green
        case .idle: return .gray.opacity(0.15)
        }
    }

    private var barLabel: String {
        switch state.transport {
        case .thunderbolt:
            if let tb = tbLink {
                return "CIO \u{00B7} \(tb.perLaneGbps) Gbps"
            }
            return "CIO"
        case .displayPort:
            let rate = Self.formatDPLinkRate(dpLinkRate)
            if !rate.isEmpty {
                return "DP \u{00B7} \(rate)"
            }
            return "DisplayPort"
        case .usb:
            let speed = usbSpeed?.label ?? "5 Gbps"
            return "USB3 \u{00B7} \(speed)"
        case .idle:
            return ""
        }
    }

    // Parse "5.40Gbps/lane (HBR2)" into "5.4 Gbps"
    static func formatDPLinkRate(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        // Extract the numeric Gbps value before "/lane"
        guard let slashIdx = raw.firstIndex(of: "/") else { return raw }
        let prefix = String(raw[raw.startIndex..<slashIdx])
            .replacingOccurrences(of: "Gbps", with: "")
        // Parse and re-format to drop trailing zeros (5.40 -> 5.4)
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
            Text("USB2")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(active ? Color.green.opacity(0.7) : Color.gray.opacity(0.15))
                .frame(height: 18)
                .overlay {
                    if active {
                        Text("480 Mbps")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
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
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
