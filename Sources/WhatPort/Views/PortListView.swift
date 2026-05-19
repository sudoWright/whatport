import SwiftUI
import WhatPortCore

struct PortListView: View {
    var portManager: PortManager
    @State private var selectedPortID: Int?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                settingsPanel
            } else if let selectedID = selectedPortID,
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
                Spacer()
            } else {
                ScrollView {
                    portList
                }
            }
            Divider()
            footer
        }
        .frame(height: 420)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Ports")
                .font(.title3.weight(.semibold))
            Spacer()
            if portManager.portCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(portManager.activePortCount)/\(portManager.portCount) active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if portManager.totalWatts > 0 {
                        Text(String(format: "%.1fW total", portManager.totalWatts))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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
        VStack(spacing: 4) {
            ForEach(portManager.ports) { port in
                PortRowView(
                    port: port,
                    isCharging: portManager.isCharging,
                    fullyCharged: portManager.fullyCharged
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPortID = port.id
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings = true
                }
            } label: {
                Image(systemName: "gear")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Detail View

    private func detailView(port: PortState) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPortID = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.body)
                    .frame(minHeight: 32)
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
                powerMeteringAvailable: portManager.powerMeteringAvailable,
                isCharging: portManager.isCharging,
                fullyCharged: portManager.fullyCharged
            )
        }
        .frame(height: 560)
    }
    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            SettingsView()
        }
        .frame(height: 420)
    }
}

// MARK: - Port Row

struct PortRowView: View {
    let port: PortState
    var isCharging: Bool = false
    var fullyCharged: Bool = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            protocolIndicator
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(titleText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(port.isActive ? .primary : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Show port number next to device name so you know which port
                    if port.deviceName != nil && port.isActive {
                        Text(portLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(port.isActive ? .secondary : .quaternary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let power = port.power {
                Text(formatWatts(power.watts))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(isHovered ? .tertiary : .quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if port.isActive || isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowFill)
            }
        }
        .overlay {
            if port.isActive || isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .padding(.horizontal, 6)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // Neutral gray cards. No protocol color in the fill.
    private var rowFill: Color {
        if isHovered {
            return Color.primary.opacity(0.08)
        }
        return Color.primary.opacity(0.04)
    }

    // When a device is connected, promote its name to the title line.
    // Falls back to the port label (Port 1, MagSafe, etc).
    private var titleText: String {
        if let device = port.deviceName, port.isActive {
            return device
        }
        return portLabel
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
            .frame(width: 12, height: 12)
    }

    private var indicatorColor: Color {
        switch port.primaryProtocol {
        case .thunderbolt: return .blue
        case .displayPort: return .orange
        case .usbOnly: return .green
        case .charging: return .yellow
        case .idle: return .gray.opacity(0.4)
        }
    }

    // Protocol and speed only. Device name is in the title now,
    // so this line stays short enough to fit without truncation.
    private var summaryText: String {
        guard port.isActive else { return "idle" }

        if let tb = port.thunderboltLink {
            let lanes = formatLanes(tx: tb.txLanes, rx: tb.rxLanes)
            return "\(tb.generation.label) \(lanes), \(tb.totalGbps) Gbps"
        }

        if port.lane0.transport == .displayPort || port.lane1.transport == .displayPort {
            let dpLive = port.liveTransports.first { $0.kind == .displayPort }
            if let dp = dpLive, !dp.dataRate.isEmpty {
                let lanes = dp.laneCount > 0 ? ", \(dp.laneCount) lane\(dp.laneCount > 1 ? "s" : "")" : ""
                return "DP alt-mode, \(dp.dataRate)\(lanes)"
            }
            let dpLanes = [port.lane0, port.lane1].filter { $0.transport == .displayPort }.count
            return "DP alt-mode, \(dpLanes) lane\(dpLanes > 1 ? "s" : "")"
        }

        if port.lane0.transport == .usb || port.lane1.transport == .usb {
            let usbLive = port.liveTransports.first { $0.kind == .usb }
            if let usb = usbLive, !usb.dataRate.isEmpty {
                return "USB3, \(usb.dataRate)"
            }
            let speed = port.usbSpeed?.label ?? "5 Gbps"
            return "USB3, \(speed)"
        }

        if port.usb2Active {
            return "USB2, 480 Mbps"
        }

        if port.ccConnected {
            if port.primaryProtocol == .charging {
                if fullyCharged { return "Battery Full" }
                if isCharging { return "Charging" }
                return "Charger Connected"
            }
            return "connected"
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
