import SwiftUI
import Charts
import WhatPortCore

struct PortDetailView: View {
    let port: PortState
    let powerHistory: [PowerSample]
    let powerMeteringAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            laneDiagram
            Divider()
            powerSection
            if !powerHistory.isEmpty {
                powerChart
            }
            if let name = port.deviceName {
                Divider()
                deviceSection(name: name)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Circle()
                .fill(protocolColor)
                .frame(width: 10, height: 10)
            Text("Port \(port.id)")
                .font(.headline)
            Spacer()
            Text(protocolLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    // MARK: - Device

    private func deviceSection(name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Connected")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text(name)
                .font(.body)
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
