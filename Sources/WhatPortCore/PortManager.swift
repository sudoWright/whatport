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
            powerData: snapshot.powerData
        )

        if portCount == 0 {
            portCount = correlated.count
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
        ports.filter(\.isActive).count
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
    public let powerMeteringAvailable: Bool

    public init(
        timestamp: Date = .now,
        phyData: [PhyInput] = [],
        tbData: [ThunderboltInput] = [],
        powerData: [PowerInput] = [],
        powerMeteringAvailable: Bool = false
    ) {
        self.timestamp = timestamp
        self.phyData = phyData
        self.tbData = tbData
        self.powerData = powerData
        self.powerMeteringAvailable = powerMeteringAvailable
    }
}

public struct PhyInput: Sendable {
    public let phyID: Int
    public let lane0Transport: String
    public let lane0PowerLevel: String
    public let lane0Client: String
    public let lane1Transport: String
    public let lane1PowerLevel: String
    public let lane1Client: String
    public let usb2Transport: String

    public init(
        phyID: Int,
        lane0Transport: String = "",
        lane0PowerLevel: String = "",
        lane0Client: String = "",
        lane1Transport: String = "",
        lane1PowerLevel: String = "",
        lane1Client: String = "",
        usb2Transport: String = ""
    ) {
        self.phyID = phyID
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
    // We use Socket ID as the canonical port identifier, then match PHY data
    // by position (PhyID order maps to Socket ID order on tested hardware).
    private func correlate(
        phyData: [PhyInput],
        tbData: [ThunderboltInput],
        powerData: [PowerInput]
    ) -> [PortState] {
        // Deduplicate TB data by socket ID (multiple adapters per port, take best)
        let tbBySocket = bestTBPerSocket(tbData)

        // Get unique socket IDs sorted (these are our physical ports)
        let socketIDs = tbBySocket.keys.sorted()

        // If no TB data, fall back to PHY IDs as port numbers
        if socketIDs.isEmpty {
            return phyData.map { phy in
                buildPortState(
                    portID: phy.phyID + 1,
                    phy: phy,
                    tb: nil,
                    power: powerData.first { $0.portIndex == phy.phyID + 1 }
                )
            }
        }

        // Correlate: PHY instances sorted by ID map to sockets sorted by ID.
        // e.g. PHY 0,1,2,3 maps to Socket 1,2,4 (first 3 PHYs = USB-C ports)
        var results: [PortState] = []
        for (index, socketID) in socketIDs.enumerated() {
            let phy = index < phyData.count ? phyData[index] : nil
            let tb = tbBySocket[socketID]
            let power = powerData.first { $0.portIndex == socketID }

            results.append(buildPortState(
                portID: socketID,
                phy: phy,
                tb: tb,
                power: power
            ))
        }

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

    private func buildPortState(
        portID: Int,
        phy: PhyInput?,
        tb: ThunderboltInput?,
        power: PowerInput?
    ) -> PortState {
        let lane0 = parseLane(transport: phy?.lane0Transport, powerLevel: phy?.lane0PowerLevel, client: phy?.lane0Client)
        let lane1 = parseLane(transport: phy?.lane1Transport, powerLevel: phy?.lane1PowerLevel, client: phy?.lane1Client)
        let usb2Active = phy.map { !$0.usb2Transport.isEmpty } ?? false

        var tbLink: ThunderboltLinkState?
        if let tb, tb.currentLinkWidth > 0, tb.currentLinkSpeed > 0 {
            let gen = TBGeneration(speedCode: tb.currentLinkSpeed)
            tbLink = ThunderboltLinkState(
                generation: gen,
                perLaneGbps: gen.perLaneGbps,
                txLanes: tb.currentLinkWidth,
                rxLanes: tb.currentLinkWidth
            )
        }

        var portPower: PortPower?
        if let pwr = power, pwr.watts > 0 {
            portPower = PortPower(
                watts: Double(pwr.watts) / 100.0,
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
            thunderboltLink: tbLink,
            power: portPower
        )
    }

    private func parseLane(transport: String?, powerLevel: String?, client: String?) -> LaneState {
        let t = transport ?? ""
        let laneTransport: LaneTransport
        switch t.lowercased() {
        case "cio": laneTransport = .thunderbolt
        case "displayport": laneTransport = .displayPort
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
