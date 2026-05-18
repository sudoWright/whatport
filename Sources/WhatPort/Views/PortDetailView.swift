import SwiftUI
import Charts
import WhatPortCore

struct PortDetailView: View {
    let port: PortState
    let powerHistory: [PowerSample]
    let powerMeteringAvailable: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()

                if let device = port.usbDevice {
                    deviceSection(device)
                    Divider()
                }

                laneDiagram
                Divider()

                powerSection
                if !powerHistory.isEmpty {
                    powerChart
                }

                if let tb = port.thunderboltCapability {
                    Divider()
                    thunderboltSection(capability: tb, link: port.thunderboltLink)
                }

                if let cable = port.cable {
                    Divider()
                    cableSection(cable)
                }

                if let stats = port.portStats {
                    Divider()
                    statsSection(stats)
                }
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
        case .charging: return "Charging"
        case .idle: return "idle"
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

    // MARK: - Lane Diagram

    private var laneDiagram: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lanes")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            LaneBar(label: "Lane 0", state: port.lane0, tbLink: port.thunderboltLink)
            LaneBar(label: "Lane 1", state: port.lane1, tbLink: port.thunderboltLink)
            USB2Bar(active: port.usb2Active)
        }
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

    // MARK: - Port Statistics

    private func statsSection(_ stats: PortStatistics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Port Statistics")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                LabeledValue(label: "Connections", value: "\(stats.connectCount)")
                if stats.overcurrentCount > 0 {
                    LabeledValue(label: "Overcurrent", value: "\(stats.overcurrentCount)")
                }
                if stats.linkErrorCount > 0 {
                    LabeledValue(label: "Link Errors", value: "\(stats.linkErrorCount)")
                }
                if stats.enumerationFailureCount > 0 {
                    LabeledValue(label: "Enum Failures", value: "\(stats.enumerationFailureCount)")
                }
            }

            // Only show error counts row if there are any errors
            if stats.overcurrentCount == 0 && stats.linkErrorCount == 0
                && stats.enumerationFailureCount == 0 && stats.addressFailureCount == 0 {
                Text("No errors")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Lane Bar

struct LaneBar: View {
    let label: String
    let state: LaneState
    let tbLink: ThunderboltLinkState?

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

            Text(speedLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)
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
        case .thunderbolt: return "CIO"
        case .displayPort: return "DisplayPort"
        case .usb: return "USB3"
        case .idle: return ""
        }
    }

    private var speedLabel: String {
        switch state.transport {
        case .thunderbolt:
            if let tb = tbLink {
                return "\(tb.perLaneGbps) Gbps"
            }
            return ""
        case .displayPort:
            return "DP"
        case .usb:
            return "5 Gbps"
        case .idle:
            return ""
        }
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
                        Text("active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }

            Text("")
                .frame(width: 70)
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
