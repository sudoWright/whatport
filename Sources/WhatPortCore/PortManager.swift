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

    // Battery / charging state (system-level, not per-port)
    public private(set) var isCharging: Bool = false
    public private(set) var fullyCharged: Bool = false

    // Power history for sparkline graphs (per port ID)
    public private(set) var powerHistory: [Int: [PowerSample]] = [:]

    private let maxPowerSamples = 20

    // Port recorder: stores long-running history and events.
    // When nil, recording is disabled (no-op). Set by the Pro plugin
    // via PluginRegistry's portManagerHooks.
    public var recorder: (any PortRecorder)?

    public init() {}

    // Called by the IOKit layer (or mock) whenever new data arrives.
    // This is the single entry point for all state updates.
    public func applySnapshot(_ snapshot: PortManagerSnapshot) {
        powerMeteringAvailable = snapshot.powerMeteringAvailable
        isCharging = snapshot.chargingPower?.isCharging ?? false
        fullyCharged = snapshot.chargingPower?.fullyCharged ?? false

        let correlated = correlate(
            hpmPorts: snapshot.hpmPorts,
            phyData: snapshot.phyData,
            tbData: snapshot.tbData,
            powerData: snapshot.powerData,
            ccData: snapshot.ccData,
            chargerData: snapshot.chargerData,
            chargingPower: snapshot.chargingPower,
            deviceData: snapshot.deviceData,
            displayData: snapshot.displayData,
            portStatsData: snapshot.portStatsData,
            usb3Transport: snapshot.usb3Transport,
            dpTransport: snapshot.dpTransport,
            cioTransport: snapshot.cioTransport,
            smcPortPower: snapshot.smcPortPower
        )

        // Flight Recorder: record before updating published state so the
        // recorder can diff old ports vs new correlated ports.
        recorder?.recordSnapshot(ports: correlated, timestamp: snapshot.timestamp)

        portCount = correlated.count

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
        ports.filter { $0.isActive }.count
    }

    // Sum of watts across all ports that are sourcing/sinking power
    public var totalWatts: Double {
        ports.compactMap { $0.power?.watts }.reduce(0, +)
    }
}

// MARK: - Snapshot input type (decoupled from IOKit raw types)

// This is what the IOKit layer passes to the domain layer.
// It mirrors the IOKit PortSnapshot but uses simpler types that
// don't require importing the IOKit module.
public struct PortManagerSnapshot: Sendable {
    public let timestamp: Date
    public let hpmPorts: [HPMPortInput]
    public let phyData: [PhyInput]
    public let tbData: [ThunderboltInput]
    public let powerData: [PowerInput]
    public let ccData: [CCInput]
    public let chargerData: [ChargerInput]
    public let chargingPower: ChargingPowerInput?
    public let deviceData: [DeviceInput]
    public let displayData: [DisplayInput]
    public let portStatsData: [PortStatsInput]
    public let powerMeteringAvailable: Bool
    // Live transport state from IOPortTransportState* services
    public let usb3Transport: [USB3TransportInput]
    public let dpTransport: [DPTransportInput]
    public let cioTransport: [CIOTransportInput]
    public let smcPortPower: [SMCPortPowerInput]

    public init(
        timestamp: Date = .now,
        hpmPorts: [HPMPortInput] = [],
        phyData: [PhyInput] = [],
        tbData: [ThunderboltInput] = [],
        powerData: [PowerInput] = [],
        ccData: [CCInput] = [],
        chargerData: [ChargerInput] = [],
        chargingPower: ChargingPowerInput? = nil,
        deviceData: [DeviceInput] = [],
        displayData: [DisplayInput] = [],
        portStatsData: [PortStatsInput] = [],
        powerMeteringAvailable: Bool = false,
        usb3Transport: [USB3TransportInput] = [],
        dpTransport: [DPTransportInput] = [],
        cioTransport: [CIOTransportInput] = [],
        smcPortPower: [SMCPortPowerInput] = []
    ) {
        self.timestamp = timestamp
        self.hpmPorts = hpmPorts
        self.phyData = phyData
        self.tbData = tbData
        self.powerData = powerData
        self.ccData = ccData
        self.chargerData = chargerData
        self.chargingPower = chargingPower
        self.deviceData = deviceData
        self.displayData = displayData
        self.portStatsData = portStatsData
        self.powerMeteringAvailable = powerMeteringAvailable
        self.usb3Transport = usb3Transport
        self.dpTransport = dpTransport
        self.cioTransport = cioTransport
        self.smcPortPower = smcPortPower
    }
}

public struct CCInput: Sendable {
    public let portNumber: Int
    public let portType: String   // "USB-C", "MagSafe 3", etc.
    public let active: Bool
    public let cableProductType: String
    public let cablePDRevision: Int

    public init(
        portNumber: Int,
        portType: String = "USB-C",
        active: Bool,
        cableProductType: String = "",
        cablePDRevision: Int = 0
    ) {
        self.portNumber = portNumber
        self.portType = portType
        self.active = active
        self.cableProductType = cableProductType
        self.cablePDRevision = cablePDRevision
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
    // DP link rate from PHY pixel clock data, e.g. "5.40Gbps/lane (HBR2)"
    public let dpLinkRate: String

    public init(
        phyID: Int,
        portNumber: Int = 0,
        lane0Transport: String = "",
        lane0PowerLevel: String = "",
        lane0Client: String = "",
        lane1Transport: String = "",
        lane1PowerLevel: String = "",
        lane1Client: String = "",
        usb2Transport: String = "",
        dpLinkRate: String = ""
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
        self.dpLinkRate = dpLinkRate
    }
}

public struct ThunderboltInput: Sendable {
    public let socketID: Int
    public let currentLinkWidth: Int
    public let currentLinkSpeed: Int
    public let supportedLinkWidth: Int
    public let supportedLinkSpeed: Int
    public let thunderboltVersion: Int
    public let dualLinkPort: Int

    public init(
        socketID: Int,
        currentLinkWidth: Int = 0,
        currentLinkSpeed: Int = 0,
        supportedLinkWidth: Int = 0,
        supportedLinkSpeed: Int = 0,
        thunderboltVersion: Int = 0,
        dualLinkPort: Int = 0
    ) {
        self.socketID = socketID
        self.currentLinkWidth = currentLinkWidth
        self.currentLinkSpeed = currentLinkSpeed
        self.supportedLinkWidth = supportedLinkWidth
        self.supportedLinkSpeed = supportedLinkSpeed
        self.thunderboltVersion = thunderboltVersion
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

// One physical port from the HPM controller layer. The authoritative port
// roster, carrying the stable UUID identity.
public struct HPMPortInput: Sendable {
    public let uuid: String
    public let portNumber: Int
    public let portType: String   // "USB-C", "MagSafe 3", etc.

    public var isMagSafe: Bool {
        portType.lowercased().contains("magsafe")
    }

    public init(uuid: String, portNumber: Int, portType: String) {
        self.uuid = uuid
        self.portNumber = portNumber
        self.portType = portType
    }
}

// One SMC per-port power-OUT channel. Tied to a physical port by `uuid`
// (the channel's DxUI = the port's HPM UUID), since the SMC D-index does not
// equal the physical port number.
public struct SMCPortPowerInput: Sendable {
    public let present: Bool
    public let volts: Double
    public let amps: Double
    public let uuid: String   // 32-char lowercase hex (normalised)

    public var watts: Double { volts * amps }

    public init(present: Bool, volts: Double, amps: Double, uuid: String) {
        self.present = present
        self.volts = volts
        self.amps = amps
        self.uuid = uuid
    }
}

public struct ChargerInput: Sendable {
    public let portType: String   // "MagSafe 3", "USB-C", etc.
    public let portNumber: Int
    public let maxWatts: Int      // milliwatts
    public let voltage: Int       // millivolts
    public let maxCurrent: Int    // milliamps

    public init(
        portType: String,
        portNumber: Int,
        maxWatts: Int = 0,
        voltage: Int = 0,
        maxCurrent: Int = 0
    ) {
        self.portType = portType
        self.portNumber = portNumber
        self.maxWatts = maxWatts
        self.voltage = voltage
        self.maxCurrent = maxCurrent
    }
}

// Live charging power from PowerTelemetryData on AppleSmartBattery.
// System-level (not per-port): represents total power drawn from the
// active charger. Only one charger supplies power at a time.
public struct ChargingPowerInput: Sendable {
    public let systemPowerIn: Int     // milliwatts
    public let systemVoltageIn: Int   // millivolts
    public let systemCurrentIn: Int   // milliamps
    public let isCharging: Bool       // battery is actively charging
    public let fullyCharged: Bool     // battery is full

    public init(
        systemPowerIn: Int,
        systemVoltageIn: Int,
        systemCurrentIn: Int,
        isCharging: Bool = false,
        fullyCharged: Bool = false
    ) {
        self.systemPowerIn = systemPowerIn
        self.systemVoltageIn = systemVoltageIn
        self.systemCurrentIn = systemCurrentIn
        self.isCharging = isCharging
        self.fullyCharged = fullyCharged
    }
}

public struct DeviceInput: Sendable {
    public let portNumber: Int
    public let productName: String
    public let vendorName: String
    public let speedCode: Int       // USB Device Speed enum
    public let usbVersion: Int      // bcdUSB (e.g. 800 = USB 3.2)
    public let currentDraw: Int     // mA allocated
    public let serialNumber: String

    public init(
        portNumber: Int,
        productName: String,
        vendorName: String = "",
        speedCode: Int = 0,
        usbVersion: Int = 0,
        currentDraw: Int = 0,
        serialNumber: String = ""
    ) {
        self.portNumber = portNumber
        self.productName = productName
        self.vendorName = vendorName
        self.speedCode = speedCode
        self.usbVersion = usbVersion
        self.currentDraw = currentDraw
        self.serialNumber = serialNumber
    }
}

public struct DisplayInput: Sendable {
    public let portNumber: Int
    public let productName: String
    public let maxWidth: Int
    public let maxHeight: Int

    public init(
        portNumber: Int,
        productName: String,
        maxWidth: Int = 0,
        maxHeight: Int = 0
    ) {
        self.portNumber = portNumber
        self.productName = productName
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
    }
}

public struct PortStatsInput: Sendable {
    public let portNumber: Int
    public let connectCount: Int
    public let overcurrentCount: Int
    public let enumerationFailureCount: Int
    public let addressFailureCount: Int
    public let linkErrorCount: Int
    public let remoteWakeCount: Int

    public init(
        portNumber: Int,
        connectCount: Int = 0,
        overcurrentCount: Int = 0,
        enumerationFailureCount: Int = 0,
        addressFailureCount: Int = 0,
        linkErrorCount: Int = 0,
        remoteWakeCount: Int = 0
    ) {
        self.portNumber = portNumber
        self.connectCount = connectCount
        self.overcurrentCount = overcurrentCount
        self.enumerationFailureCount = enumerationFailureCount
        self.addressFailureCount = addressFailureCount
        self.linkErrorCount = linkErrorCount
        self.remoteWakeCount = remoteWakeCount
    }
}

// MARK: - Live transport state inputs

public struct USB3TransportInput: Sendable {
    public let portNumber: Int
    public let active: Bool
    public let dataRate: String          // "10 Gbps"
    public let generation: String        // "Gen 2"
    public let generationFamily: String  // "USB 3.x"
    public let tunneled: Bool
    public let transportRestricted: Bool // macOS TRM has blocked data

    public init(
        portNumber: Int,
        active: Bool = false,
        dataRate: String = "",
        generation: String = "",
        generationFamily: String = "",
        tunneled: Bool = false,
        transportRestricted: Bool = false
    ) {
        self.portNumber = portNumber
        self.active = active
        self.dataRate = dataRate
        self.generation = generation
        self.generationFamily = generationFamily
        self.tunneled = tunneled
        self.transportRestricted = transportRestricted
    }
}

public struct DPTransportInput: Sendable {
    public let portNumber: Int
    public let active: Bool
    public let linkRate: String          // "5.4 Gbps (HBR2)"
    public let laneCount: Int
    public let maxLaneCount: Int
    public let tunneled: Bool
    public let sinkCount: Int

    public init(
        portNumber: Int,
        active: Bool = false,
        linkRate: String = "",
        laneCount: Int = 0,
        maxLaneCount: Int = 0,
        tunneled: Bool = false,
        sinkCount: Int = 0
    ) {
        self.portNumber = portNumber
        self.active = active
        self.linkRate = linkRate
        self.laneCount = laneCount
        self.maxLaneCount = maxLaneCount
        self.tunneled = tunneled
        self.sinkCount = sinkCount
    }
}

public struct CIOTransportInput: Sendable {
    public let portNumber: Int
    public let active: Bool
    public let dataRate: String
    public let tunneled: Bool

    public init(
        portNumber: Int,
        active: Bool = false,
        dataRate: String = "",
        tunneled: Bool = false
    ) {
        self.portNumber = portNumber
        self.active = active
        self.dataRate = dataRate
        self.tunneled = tunneled
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
        hpmPorts: [HPMPortInput] = [],
        phyData: [PhyInput],
        tbData: [ThunderboltInput],
        powerData: [PowerInput],
        ccData: [CCInput],
        chargerData: [ChargerInput] = [],
        chargingPower: ChargingPowerInput? = nil,
        deviceData: [DeviceInput] = [],
        displayData: [DisplayInput] = [],
        portStatsData: [PortStatsInput] = [],
        usb3Transport: [USB3TransportInput] = [],
        dpTransport: [DPTransportInput] = [],
        cioTransport: [CIOTransportInput] = [],
        smcPortPower: [SMCPortPowerInput] = []
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

        // Build PHY lookup for direct mapping
        let phyByPort: [Int: PhyInput] = hasDirectMapping
            ? Dictionary(
                dedupedPhys.compactMap { $0.portNumber > 0 ? ($0.portNumber, $0) : nil },
                uniquingKeysWith: { existing, _ in existing }
              )
            : [:]

        // Picks the PHY for a port: direct by port number, else positional.
        func phyFor(portNumber: Int, index: Int) -> PhyInput? {
            if hasDirectMapping { return phyByPort[portNumber] }
            return index < dedupedPhys.count ? dedupedPhys[index] : nil
        }

        // Build the USB-C port roster. The HPM controller layer is the
        // authoritative source of physical ports and their stable UUID, so we
        // prefer it. When there is no HPM node (Intel, desktop front ports, or
        // tests) we fall back to Thunderbolt socket IDs, then PHY port numbers.
        // All sources key the per-port data by the same "@N" number, which
        // agrees across the HPM / PHY / TB / transport trees.
        let usbcHPM = hpmPorts.filter { !$0.isMagSafe }.sorted { $0.portNumber < $1.portNumber }
        var results: [PortState]

        if !usbcHPM.isEmpty {
            results = usbcHPM.enumerated().map { index, hpm in
                var state = buildPortState(
                    portID: hpm.portNumber,
                    phy: phyFor(portNumber: hpm.portNumber, index: index),
                    tb: tbBySocket[hpm.portNumber],
                    power: powerData.first { $0.portIndex == hpm.portNumber },
                    ccActive: ccByPort[hpm.portNumber] ?? false
                )
                state.uuid = hpm.uuid
                return state
            }
        } else if !socketIDs.isEmpty {
            results = socketIDs.enumerated().map { index, socketID in
                buildPortState(
                    portID: socketID,
                    phy: phyFor(portNumber: socketID, index: index),
                    tb: tbBySocket[socketID],
                    power: powerData.first { $0.portIndex == socketID },
                    ccActive: ccByPort[socketID] ?? false
                )
            }
        } else {
            results = dedupedPhys.map { phy in
                let portID = phy.portNumber > 0 ? phy.portNumber : (phy.phyID + 1)
                return buildPortState(
                    portID: portID,
                    phy: phy,
                    tb: nil,
                    power: powerData.first { $0.portIndex == portID },
                    ccActive: ccByPort[portID] ?? false
                )
            }
        }

        // Attach charger power to the USB-C port that negotiated a USB-PD
        // contract (power flows IN, so it never shows in PowerOutDetails).
        applyChargerPower(to: &results, chargerData: chargerData, chargingPower: chargingPower)

        // Append non-USB-C ports (MagSafe, etc.), stamping their HPM UUID.
        var nonUSBC = buildNonUSBCPorts(nonUSBCCC, chargerData: chargerData, chargingPower: chargingPower)
        stampMagSafeUUIDs(&nonUSBC, hpmPorts: hpmPorts)
        results.append(contentsOf: nonUSBC)

        // Desktop power-OUT: join SMC channels to ports by UUID. The SMC
        // D-index is not the physical port number, so the channel's DxUI (=
        // the port's HPM UUID) is the only correct join. Fills power the
        // battery paths can't (Mac mini / Studio, or any Mac sourcing bus
        // power), so it runs after the charger/battery power is applied.
        applySMCPower(to: &results, smcPortPower: smcPortPower)

        // Build lookup dictionaries for enrichment data
        let devicesByPort = Dictionary(
            deviceData.map { ($0.portNumber, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let displaysByPort = Dictionary(
            displayData.map { ($0.portNumber, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let statsByPort = Dictionary(
            portStatsData.map { ($0.portNumber, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let ccByPortFull = Dictionary(
            usbCCC.map { ($0.portNumber, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        for i in results.indices {
            let portID = results[i].id

            // Display name takes priority over USB device name since a USB
            // device on a TB/DP port is usually the hub, not the display.
            if let display = displaysByPort[portID] {
                results[i].deviceName = display.productName
                results[i].displayWidth = display.maxWidth
                results[i].displayHeight = display.maxHeight
            } else if let device = devicesByPort[portID] {
                results[i].deviceName = device.productName
                if device.speedCode > 0 {
                    results[i].usbSpeed = USBSpeed(code: device.speedCode)
                }
            }

            // Full USB device info for the detail view
            if let device = devicesByPort[portID] {
                let speed = device.speedCode > 0 ? USBSpeed(code: device.speedCode) : nil
                results[i].usbDevice = USBDeviceInfo(
                    productName: device.productName,
                    vendorName: device.vendorName,
                    serialNumber: device.serialNumber.isEmpty ? nil : device.serialNumber,
                    speed: speed,
                    usbVersion: formatBcdUSB(device.usbVersion),
                    currentDraw: device.currentDraw
                )
            }

            // Cable identity from CC SOP' data
            if let cc = ccByPortFull[portID], !cc.cableProductType.isEmpty {
                results[i].cable = CableInfo(
                    productType: cc.cableProductType,
                    pdRevision: cc.cablePDRevision
                )
            }

            // Port statistics (lifetime counters)
            if let stats = statsByPort[portID] {
                results[i].portStats = PortStatistics(
                    connectCount: stats.connectCount,
                    overcurrentCount: stats.overcurrentCount,
                    enumerationFailureCount: stats.enumerationFailureCount,
                    addressFailureCount: stats.addressFailureCount,
                    linkErrorCount: stats.linkErrorCount,
                    remoteWakeCount: stats.remoteWakeCount
                )
            }

            // TB port capability (supported speed/width even when no link active)
            if let tb = tbBySocket[portID] {
                results[i].thunderboltCapability = ThunderboltCapability(
                    supportedLinkSpeed: tb.supportedLinkSpeed,
                    supportedLinkWidth: tb.supportedLinkWidth,
                    thunderboltVersion: tb.thunderboltVersion
                )
            }

            // Live transport state (real-time link data per transport)
            results[i].liveTransports = buildLiveTransports(
                portID: portID,
                usb3Transport: usb3Transport,
                dpTransport: dpTransport,
                cioTransport: cioTransport
            )
        }

        return results
    }

    // Build LiveTransport entries for a port from the transport state services.
    // Only includes transports that are active on this port.
    private func buildLiveTransports(
        portID: Int,
        usb3Transport: [USB3TransportInput],
        dpTransport: [DPTransportInput],
        cioTransport: [CIOTransportInput]
    ) -> [LiveTransport] {
        var transports: [LiveTransport] = []

        // Include a restricted link even when it is not active: macOS has
        // negotiated a speed but blocked data, and we want to show that
        // rather than silently dropping the port as idle.
        if let usb3 = usb3Transport.first(where: {
            $0.portNumber == portID && ($0.active || $0.transportRestricted)
        }) {
            transports.append(LiveTransport(
                kind: .usb,
                dataRate: usb3.dataRate,
                generation: usb3.generation,
                tunneled: usb3.tunneled,
                restricted: usb3.transportRestricted
            ))
        }

        if let dp = dpTransport.first(where: { $0.portNumber == portID && $0.active }) {
            transports.append(LiveTransport(
                kind: .displayPort,
                dataRate: dp.linkRate,
                laneCount: dp.laneCount,
                maxLaneCount: dp.maxLaneCount,
                tunneled: dp.tunneled
            ))
        }

        if let cio = cioTransport.first(where: { $0.portNumber == portID && $0.active }) {
            transports.append(LiveTransport(
                kind: .thunderbolt,
                dataRate: cio.dataRate,
                tunneled: cio.tunneled
            ))
        }

        return transports
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

    // Attach charger (power-IN) data to the USB-C port that negotiated a
    // USB-PD source contract. PowerOutDetails only covers power the Mac
    // delivers OUT to bus-powered devices; a charger supplies power IN, so
    // it never appears there. On Macs without PowerOutDetails (e.g. base M5)
    // this IOPortFeaturePowerSource contract is the only per-port power
    // signal we get. We show the negotiated contract (volts / amps) plus the
    // live draw from PowerTelemetryData, which is near zero when the battery
    // is full and ramps up while charging.
    //
    // Only the port with an actual USB-PD contract gets power. This is also
    // what stops a bare cable (CC active, no contract) from being treated as
    // a charger and inheriting the system battery state.
    private func applyChargerPower(
        to results: inout [PortState],
        chargerData: [ChargerInput],
        chargingPower: ChargingPowerInput?
    ) {
        let usbcChargers = Dictionary(
            chargerData
                .filter { $0.portType == "USB-C" && $0.portNumber > 0 }
                .map { ($0.portNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !usbcChargers.isEmpty else { return }

        for i in results.indices {
            guard results[i].power == nil, results[i].ccConnected else { continue }
            guard let charger = usbcChargers[results[i].id] else { continue }

            results[i].power = PortPower(
                watts: Double(chargingPower?.systemPowerIn ?? 0) / 1000.0,
                current: chargingPower?.systemCurrentIn ?? 0,
                voltage: chargingPower?.systemVoltageIn ?? charger.voltage,
                configuredVoltage: charger.voltage,
                configuredCurrent: charger.maxCurrent,
                vconnCurrent: 0
            )
        }
    }

    // Join SMC per-port power-OUT channels to ports by UUID and fill the power
    // of any port the battery paths didn't cover. The SMC reports power the Mac
    // delivers OUT to bus-powered devices; on desktops (no battery) it is the
    // only per-port power source. Matched on the channel's DxUI = the port's
    // HPM UUID, never the SMC D-index (which is not the physical port number).
    private func applySMCPower(to results: inout [PortState], smcPortPower: [SMCPortPowerInput]) {
        guard !smcPortPower.isEmpty else { return }

        // SMC UUIDs arrive already normalised (lowercase, no dashes).
        let byUUID = Dictionary(
            smcPortPower.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for i in results.indices {
            guard results[i].power == nil, let uuid = results[i].uuid else { continue }
            guard let channel = byUUID[normalisedUUID(uuid)] else { continue }
            // Only surface a reading when the Mac is actually sourcing power.
            // A channel at 0 W means nothing is drawing; leave power nil so the
            // UI shows "not sourcing" rather than a misleading 0.0 W.
            guard channel.watts > 0 else { continue }

            results[i].power = PortPower(
                watts: channel.watts,
                current: Int((channel.amps * 1000).rounded()),
                voltage: Int((channel.volts * 1000).rounded()),
                configuredVoltage: 0,
                configuredCurrent: 0,
                vconnCurrent: 0
            )
        }
    }

    // Normalise an HPM UUID to match the SMC DxUI form: dashes stripped,
    // lowercase (e.g. "6230AF2D-EE59-..." -> "6230af2dee59...").
    private func normalisedUUID(_ uuid: String) -> String {
        uuid.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // Stamp the stable HPM UUID onto non-USB-C ports (MagSafe). These ports
    // are built from CC data and keyed by id = 100 + portNumber, so we map
    // back to the physical number to look up the HPM entry. No-op without HPM.
    private func stampMagSafeUUIDs(_ ports: inout [PortState], hpmPorts: [HPMPortInput]) {
        guard !hpmPorts.isEmpty else { return }
        let magByNumber = Dictionary(
            hpmPorts.filter { $0.isMagSafe }.map { ($0.portNumber, $0.uuid) },
            uniquingKeysWith: { first, _ in first }
        )
        for i in ports.indices where ports[i].portType == .magSafe {
            if let uuid = magByNumber[ports[i].id - 100] {
                ports[i].uuid = uuid
            }
        }
    }

    // Build port entries for non-USB-C connectors (MagSafe, etc.)
    // These only have CC data, no PHY or TB. They use IDs starting at
    // 100 to avoid colliding with USB-C socket IDs.
    private func buildNonUSBCPorts(
        _ ccEntries: [CCInput],
        chargerData: [ChargerInput],
        chargingPower: ChargingPowerInput? = nil
    ) -> [PortState] {
        ccEntries.map { cc in
            let portType: PortType = cc.portType.lowercased().contains("magsafe") ? .magSafe : .usbC

            // Only show live watts when battery is actively charging
            // and the port is connected.
            var power: PortPower?
            let batteryIsCharging = chargingPower?.isCharging ?? false
            if cc.active && batteryIsCharging, let cp = chargingPower, cp.systemPowerIn > 0 {
                power = PortPower(
                    watts: Double(cp.systemPowerIn) / 1000.0,
                    current: cp.systemCurrentIn,
                    voltage: cp.systemVoltageIn,
                    configuredVoltage: cp.systemVoltageIn,
                    configuredCurrent: cp.systemCurrentIn,
                    vconnCurrent: 0
                )
            }

            return PortState(
                id: 100 + cc.portNumber,
                portType: portType,
                ccConnected: cc.active,
                power: power
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

        var state = PortState(
            id: portID,
            lane0: lane0,
            lane1: lane1,
            usb2Active: usb2Active,
            ccConnected: ccActive,
            thunderboltLink: tbLink,
            power: portPower
        )
        state.dpLinkRate = phy?.dpLinkRate ?? ""
        return state
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

    // bcdUSB is BCD-encoded: 0x0200 = 512 = USB 2.0, 0x0300 = 768 = USB 3.0,
    // 0x0310 = 784 = USB 3.1, 0x0320 = 800 = USB 3.2
    private func formatBcdUSB(_ bcd: Int) -> String {
        let major = bcd / 256
        let minor = (bcd % 256) / 16
        let patch = bcd % 16
        if patch > 0 {
            return "USB \(major).\(minor)\(patch)"
        }
        return "USB \(major).\(minor)"
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
