import SwiftUI
import WhatPortCore

struct PortListView: View {
    var portManager: PortManager
    var onSettings: (() -> Void)?
    @State private var selectedPortID: Int?

    var body: some View {
        VStack(spacing: 0) {
            if let selectedID = selectedPortID,
               let port = portManager.ports.first(where: { $0.id == selectedID }) {
                detailView(port: port)
            } else {
                listView
            }
        }
        .frame(width: 320)
    }

    // MARK: - List View

    private var listView: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if portManager.ports.isEmpty {
                emptyState
            } else {
                portList
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Ports")
                .font(.headline)
            Spacer()
            if portManager.portCount > 0 {
                Text("\(portManager.activePortCount)/\(portManager.portCount) active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Scanning ports...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var portList: some View {
        VStack(spacing: 0) {
            ForEach(portManager.ports) { port in
                PortRowView(port: port)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPortID = port.id
                    }
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer()
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gear")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Detail View

    private func detailView(port: PortState) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { selectedPortID = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            PortDetailView(
                port: port,
                powerHistory: portManager.powerHistory[port.id] ?? [],
                powerMeteringAvailable: portManager.powerMeteringAvailable
            )
        }
    }
}

// MARK: - Port Row

struct PortRowView: View {
    let port: PortState

    var body: some View {
        HStack(spacing: 10) {
            protocolIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(portLabel)
                    .font(.body.weight(.medium))
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(port.isActive ? .secondary : .tertiary)
            }
            Spacer()
            if let power = port.power {
                Text(formatWatts(power.watts))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(port.isActive ? 1.0 : 0.5)
    }

    private var portLabel: String {
        switch port.portType {
        case .magSafe: return "MagSafe"
        case .usbC: return "Port \(port.id)"
        }
    }

    private var protocolIndicator: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 10, height: 10)
    }

    private var indicatorColor: Color {
        switch port.primaryProtocol {
        case .thunderbolt: return .purple
        case .displayPort: return .orange
        case .usbOnly: return .green
        case .charging: return .yellow
        case .idle: return .gray.opacity(0.4)
        }
    }

    private var summaryText: String {
        guard port.isActive else { return "idle" }

        if let tb = port.thunderboltLink {
            let lanes = formatLanes(tx: tb.txLanes, rx: tb.rxLanes)
            return "\(tb.generation.label) \(lanes), \(tb.totalGbps) Gbps"
        }

        if port.lane0.transport == .displayPort || port.lane1.transport == .displayPort {
            let dpLanes = [port.lane0, port.lane1].filter { $0.transport == .displayPort }.count
            return "DP alt-mode, \(dpLanes) lane\(dpLanes > 1 ? "s" : "")"
        }

        if port.lane0.transport == .usb || port.lane1.transport == .usb {
            return "USB3"
        }

        if port.usb2Active {
            return "USB2"
        }

        if port.ccConnected {
            return "charging"
        }

        return "active"
    }

    private func formatLanes(tx: Int, rx: Int) -> String {
        if tx == rx {
            return tx > 1 ? "dual-lane" : "single-lane"
        }
        return "\(tx)TX/\(rx)RX"
    }

    private func formatWatts(_ watts: Double) -> String {
        if watts < 1 {
            return String(format: "%.2fW", watts)
        }
        return String(format: "%.1fW", watts)
    }
}
