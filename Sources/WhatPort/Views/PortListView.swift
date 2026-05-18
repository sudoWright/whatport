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
        .frame(width: 300)
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
            Text("USB-C Ports")
                .font(.system(.headline, design: .default))
            Spacer()
            if portManager.portCount > 0 {
                Text("\(portManager.activePortCount)/\(portManager.portCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "cable.connector")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Scanning ports...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

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
            VStack(alignment: .leading, spacing: 1) {
                Text("Port \(port.id)")
                    .font(.system(.subheadline, weight: .medium))
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(port.isActive ? .secondary : .tertiary)
            }
            Spacer()
            if let power = port.power {
                Text(formatWatts(power.watts))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .opacity(port.isActive ? 1.0 : 0.5)
    }

    private var protocolIndicator: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
    }

    private var indicatorColor: Color {
        switch port.primaryProtocol {
        case .thunderbolt: return .purple
        case .displayPort: return .orange
        case .usbOnly: return .green
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
