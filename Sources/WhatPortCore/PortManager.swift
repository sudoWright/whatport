import Foundation

// PortManager is the central domain object. It holds the current state of all
// ports and updates when new IOKit snapshots arrive.
//
// @Observable is Swift 5.9's Observation framework. It replaces the older
// ObservableObject + @Published pattern. SwiftUI views that read properties
// on an @Observable object automatically re-render when those properties change.
// No @Published wrappers needed - the macro handles it.
@Observable
public final class PortManager: @unchecked Sendable {
    public private(set) var ports: [PortState] = []
    public private(set) var portCount: Int = 0
    public private(set) var powerMeteringAvailable: Bool = false

    // Power history for sparkline graphs (per port ID)
    public private(set) var powerHistory: [Int: [PowerSample]] = [:]

    private let maxPowerSamples = 20

    public init() {}

    // Called by the IOKit layer (or mock) whenever new data arrives.
    // This is the single entry point for all state updates.
    public func applySnapshot(_ snapshot: PortManagerSnapshot) {
        powerMeteringAvailable = snapshot.powerMeteringAvailable

        let correlated = correlate(
            phyData: snapshot.phyData,
            tbData: snapshot.tbData,
            powerData: snapshot.powerData,
            ccData: snapshot.ccData
        )

        // portCount tracks USB-C ports only (stable count from hardware).
        // MagSafe and other non-USB-C ports are dynamic and excluded.
        let usbCPorts = correlated.filter { $0.portType == .usbC }
        if portCount == 0 {
            portCount = usbCPorts.count
        }

        ports = correlated

        for port in correlated {
            if let power = port.power {
                var history = powerHistory[port.id] ?? []
                history.append(PowerSample(timestamp: snapshot.timestamp, watts: power.watts))
                if history.count > maxPowerSamples {
                    history.removeFirst(history.count - maxPowerSamples)
                }
                powerHistory[port.id] = history
            }
        }
    }

    public var activePortCount: Int {
        ports.filter { $0.isActive && $0.portType == .usbC }.count
    }
}

// MARK: - Snapshot input type (decoupled from IOKit raw types)

// This is what the IOKit layer passes to the domain layer.
// It mirrors the IOKit PortSnapshot but uses simpler types that
// don't require importing the IOKit module.
public struct PortManagerSnapshot: Sendable {
    public let timestamp: Date
    public let phyData: [PhyInput]
    public let tbData: [ThunderboltInput]
    public let powerData: [PowerInput]
    public let ccData: [CCInput]
    public let powerMeteringAvailable: Bool

    public init(
        timestamp: Date = .now,
        phyData: [PhyInput] = [],
        tbData: [ThunderboltInput] = [],
        powerData: [PowerInput] = [],
        ccData: [CCInput] = [],
        powerMeteringAvailable: Bool = false
    ) {
        self.timestamp = timestamp
        self.phyData = phyData
        self.tbData = tbData
        self.powerData = powerData
        self.ccData = ccData
        self.powerMeteringAvailable = powerMeteringAvailable
    }
}

public struct CCInput: Sendable {
    public let portNumber: Int
    public let portType: String   // "USB-C", "MagSafe 3", etc.
    public let active: Bool

    public init(portNumber: Int, portType: String = "USB-C", active: Bool) {
        self.portNumber = portNumber
        self.portType = portType
        self.active = active
    }
}

public struct PhyInput: Sendable {
    public let phyID: Int
    // Direct port mapping from the device tree. 0 means unavailable.
    // When present, this is used instead of positional mapping to
    // correlate PHY data with Thunderbolt socket IDs.
    public let portNumber: Int
    public let lane0Transport: String
    public let lane0PowerLevel: String
    public let lane0Client: String
    public let lane1Transport: String
    public let lane1PowerLevel: String
    public let lane1Client: String
    public let usb2Transport: String

    public init(
        phyID: Int,
        portNumber: Int = 0,
        lane0Transport: String = "",
        lane0PowerLevel: String = "",
        lane0Client: String = "",
        lane1Transport: String = "",
        lane1PowerLevel: String = "",
        lane1Client: String = "",
        usb2Transport: String = ""
    ) {
        self.phyID = phyID
        self.portNumber = portNumber
        self.lane0Transport = lane0Transport
        self.lane0PowerLevel = lane0PowerLevel
        self.lane0Client = lane0Client
        self.lane1Transport = lane1Transport
        self.lane1PowerLevel = lane1PowerLevel
        self.lane1Client = lane1Client
        self.usb2Transport = usb2Transport
    }
}

public struct ThunderboltInput: Sendable {
    public let socketID: Int
    public let currentLinkWidth: Int
    public let currentLinkSpeed: Int
    public let dualLinkPort: Int

    public init(
        socketID: Int,
        currentLinkWidth: Int = 0,
        currentLinkSpeed: Int = 0,
        dualLinkPort: Int = 0
    ) {
        self.socketID = socketID
        self.currentLinkWidth = currentLinkWidth
        self.currentLinkSpeed = currentLinkSpeed
        self.dualLinkPort = dualLinkPort
    }
}

public struct PowerInput: Sendable {
    public let portIndex: Int
    public let watts: Int
    public let current: Int
    public let adapterVoltage: Int
    public let configuredVoltage: Int
    public let configuredCurrent: Int
    public let vconnCurrent: Int

    public init(
        portIndex: Int,
        watts: Int = 0,
        current: Int = 0,
        adapterVoltage: Int = 0,
        configuredVoltage: Int = 0,
        configuredCurrent: Int = 0,
        vconnCurrent: Int = 0
    ) {
        self.portIndex = portIndex
        self.watts = watts
        self.current = current
        self.adapterVoltage = adapterVoltage
        self.configuredVoltage = configuredVoltage
        self.configuredCurrent = configuredCurrent
        self.vconnCurrent = vconnCurrent
    }
}

// MARK: - Power sample for history graph

public struct PowerSample: Sendable {
    public let timestamp: Date
    public let watts: Double

    public init(timestamp: Date, watts: Double) {
        self.timestamp = timestamp
        self.watts = watts
    }
}

// MARK: - Correlation logic

extension PortManager {
    // Correlates PHY lane data with Thunderbolt link data and power data
    // to build a unified PortState per physical port.
    //
    // The key insight: IOThunderboltPort's Socket ID = physical port number.
    // We use Socket ID as the canonical port identifier.
    //
    // PHY-to-port mapping uses two strategies:
    // 1. Direct: if PHY data has portNumber (from the parent atc-phy device
    //    tree node), match portNumber to socketID. Confirmed on M4 Pro;
    //    not yet verified across all Mac models, but device-tree port-number
    //    is a standard ARM IOKit property so it should be universal.
    // 2. Positional fallback: PHYs sorted by ID map to sockets sorted by
    //    ID. Works when PHY count == port count but breaks when there are
    //    extra PHYs (e.g. M4 Pro has 4 PHYs for 3 ports).
    private func correlate(
        phyData: [PhyInput],
        tbData: [ThunderboltInput],
        powerData: [PowerInput],
        ccData: [CCInput]
    ) -> [PortState] {
        // Deduplicate TB data by socket ID (multiple adapters per port, take best)
        let tbBySocket = bestTBPerSocket(tbData)

        // Deduplicate PHY data by port number (multiple PHYs per port, take best)
        let dedupedPhys = bestPhyPerPort(phyData)
        let hasDirectMapping = dedupedPhys.contains { $0.portNumber > 0 }

        // Separate USB-C CC data from non-USB-C (MagSafe, etc.)
        // They can share the same ParentBuiltInPortNumber, so we must
        // not let MagSafe's state bleed into USB-C port matching.
        let usbCCC = ccData.filter { $0.portType == "USB-C" }
        let nonUSBCCC = ccData.filter { $0.portType != "USB-C" && $0.portType != "" }

        let ccByPort = Dictionary(usbCCC.map { ($0.portNumber, $0.active) }, uniquingKeysWith: { a, _ in a })

        // Get unique socket IDs sorted (these are our physical ports)
        let socketIDs = tbBySocket.keys.sorted()

        // If no TB data, use PHY port numbers (or PHY IDs + 1 as fallback)
        if socketIDs.isEmpty {
            var results = dedupedPhys.map { phy in
                let portID = phy.portNumber > 0 ? phy.portNumber : (phy.phyID + 1)
                return buildPortState(
                    portID: portID,
                    phy: phy,
                    tb: nil,
                    power: powerData.first { $0.portIndex == portID },
                    ccActive: ccByPort[portID] ?? false
                )
            }
            results.append(contentsOf: buildNonUSBCPorts(nonUSBCCC))
            return results
        }

        // Build PHY lookup for direct mapping
        let phyByPort: [Int: PhyInput] = {
            guard hasDirectMapping else { return [:] }
            return Dictionary(
                dedupedPhys.compactMap { $0.portNumber > 0 ? ($0.portNumber, $0) : nil },
                uniquingKeysWith: { existing, _ in existing }
            )
        }()

        // Correlate each socket with its PHY data
        var results: [PortState] = []
        for (index, socketID) in socketIDs.enumerated() {
            let phy: PhyInput?
            if hasDirectMapping {
                // Direct mapping: PHY portNumber matches socket ID
                phy = phyByPort[socketID]
            } else {
                // Positional fallback: PHY sorted by ID maps to socket sorted by ID
                phy = index < dedupedPhys.count ? dedupedPhys[index] : nil
            }

            let tb = tbBySocket[socketID]
            let power = powerData.first { $0.portIndex == socketID }

            results.append(buildPortState(
                portID: socketID,
                phy: phy,
                tb: tb,
                power: power,
                ccActive: ccByPort[socketID] ?? false
            ))
        }

        // Append non-USB-C ports (MagSafe, etc.) at the end
        results.append(contentsOf: buildNonUSBCPorts(nonUSBCCC))

        return results
    }

    // Multiple TB adapters exist per socket (one per lane). Pick the one
    // with the highest link width as the representative.
    private func bestTBPerSocket(_ tbData: [ThunderboltInput]) -> [Int: ThunderboltInput] {
        var best: [Int: ThunderboltInput] = [:]
        for tb in tbData {
            guard tb.socketID > 0 else { continue }
            if let existing = best[tb.socketID] {
                if tb.currentLinkWidth > existing.currentLinkWidth {
                    best[tb.socketID] = tb
                }
            } else {
                best[tb.socketID] = tb
            }
        }
        return best
    }

    // Multiple PHY controllers can map to the same physical port.
    // For example, M4 Pro has 4 PHYs for 3 ports (PHY 0 and PHY 2 both
    // map to port 1). Pick the one with active transport data.
    // If port-number isn't available, each PHY is treated as unique.
    private func bestPhyPerPort(_ phyData: [PhyInput]) -> [PhyInput] {
        let hasPortNumbers = phyData.contains { $0.portNumber > 0 }
        guard hasPortNumbers else { return phyData }

        var best: [Int: PhyInput] = [:]
        for phy in phyData {
            let key = phy.portNumber > 0 ? phy.portNumber : phy.phyID
            if let existing = best[key] {
                // Prefer the PHY with active transport
                let phyActive = !phy.lane0Transport.isEmpty || !phy.lane1Transport.isEmpty
                let existingActive = !existing.lane0Transport.isEmpty || !existing.lane1Transport.isEmpty
                if phyActive && !existingActive {
                    best[key] = phy
                }
            } else {
                best[key] = phy
            }
        }

        return best.values.sorted {
            let a = $0.portNumber > 0 ? $0.portNumber : $0.phyID
            let b = $1.portNumber > 0 ? $1.portNumber : $1.phyID
            return a < b
        }
    }

    // Build port entries for non-USB-C connectors (MagSafe, etc.)
    // These only have CC data, no PHY or TB. They use IDs starting at
    // 100 to avoid colliding with USB-C socket IDs.
    private func buildNonUSBCPorts(_ ccEntries: [CCInput]) -> [PortState] {
        ccEntries.compactMap { cc in
            guard cc.active else { return nil }
            let portType: PortType = cc.portType.lowercased().contains("magsafe") ? .magSafe : .usbC
            return PortState(
                id: 100 + cc.portNumber,
                portType: portType,
                ccConnected: true
            )
        }
    }

    private func buildPortState(
        portID: Int,
        phy: PhyInput?,
        tb: ThunderboltInput?,
        power: PowerInput?,
        ccActive: Bool
    ) -> PortState {
        let lane0 = parseLane(transport: phy?.lane0Transport, powerLevel: phy?.lane0PowerLevel, client: phy?.lane0Client)
        let lane1 = parseLane(transport: phy?.lane1Transport, powerLevel: phy?.lane1PowerLevel, client: phy?.lane1Client)
        let usb2Active = phy.map { !$0.usb2Transport.isEmpty } ?? false

        var tbLink: ThunderboltLinkState?
        if let tb, tb.currentLinkWidth > 0, tb.currentLinkSpeed > 0 {
            let gen = TBGeneration(speedCode: tb.currentLinkSpeed)
            let (tx, rx) = decodeLinkWidth(tb.currentLinkWidth)
            tbLink = ThunderboltLinkState(
                generation: gen,
                perLaneGbps: gen.perLaneGbps,
                txLanes: tx,
                rxLanes: rx
            )
        }

        var portPower: PortPower?
        if let pwr = power, pwr.watts > 0 {
            portPower = PortPower(
                watts: Double(pwr.watts) / 1000.0,
                current: pwr.current,
                voltage: pwr.adapterVoltage,
                configuredVoltage: pwr.configuredVoltage,
                configuredCurrent: pwr.configuredCurrent,
                vconnCurrent: pwr.vconnCurrent
            )
        }

        return PortState(
            id: portID,
            lane0: lane0,
            lane1: lane1,
            usb2Active: usb2Active,
            ccConnected: ccActive,
            thunderboltLink: tbLink,
            power: portPower
        )
    }

    // Current Link Width is a bitmask, not a lane count.
    // From thunderbolt-fabric.md:
    //   0x1 = single lane (1 TX, 1 RX)
    //   0x2 = dual lane (2 TX, 2 RX)
    //   0x4 = asymmetric TX (3 TX, 1 RX) - TB5 only
    //   0x8 = asymmetric RX (1 TX, 3 RX) - TB5 only
    private func decodeLinkWidth(_ width: Int) -> (tx: Int, rx: Int) {
        switch width {
        case 0x1: return (1, 1)
        case 0x2: return (2, 2)
        case 0x4: return (3, 1)  // asymmetric TX
        case 0x8: return (1, 3)  // asymmetric RX
        default: return (1, 1)
        }
    }

    private func parseLane(transport: String?, powerLevel: String?, client: String?) -> LaneState {
        let t = transport ?? ""
        let laneTransport: LaneTransport
        switch t.lowercased() {
        case "cio": laneTransport = .thunderbolt
        case "displayport": laneTransport = .displayPort
        case "usb3": laneTransport = .usb
        default: laneTransport = .idle
        }

        let power: PowerLevel = (powerLevel ?? "").lowercased() == "on" ? .on : .off

        return LaneState(
            transport: laneTransport,
            powerLevel: power,
            client: (client ?? "").isEmpty ? nil : client
        )
    }
}
