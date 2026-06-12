import Foundation

// All domain model types for WhatPort.
// These are pure value types with no IOKit or UI dependencies.

// MARK: - Port State

public struct PortState: Identifiable, Sendable {
    public let id: Int
    // Stable per-physical-port identity from the HPM controller (the "UUID"
    // property). Nil on Macs without an HPM node (Intel, desktop front ports)
    // or when the roster falls back to port-number correlation. Internal join
    // key only, never shown in the UI. Distinguishes MagSafe from USB-C when
    // they share the same port number.
    public var uuid: String?
    public var portType: PortType
    public var lane0: LaneState
    public var lane1: LaneState
    public var usb2Active: Bool
    public var ccConnected: Bool
    public var thunderboltLink: ThunderboltLinkState?
    public var power: PortPower?
    public var deviceName: String?
    public var usbSpeed: USBSpeed?
    public var usbDevice: USBDeviceInfo?
    public var cable: CableInfo?
    public var portStats: PortStatistics?
    public var thunderboltCapability: ThunderboltCapability?
    // Raw DP link rate from PHY, e.g. "5.40Gbps/lane (HBR2)". Empty when
    // no DisplayPort connection is active on this port. Fallback; prefer
    // liveTransports when available.
    public var dpLinkRate: String = ""

    // Health signals from the HPM port-controller node.
    // Nil on machines without an HPM node or when health data is unavailable.
    public var health: PortHealth?

    // Live transport state from IOPortTransportState* services.
    // One entry per active transport on this port (USB3, DP, CIO).
    public var liveTransports: [LiveTransport] = []

    // Display native resolution (from IOKit display data, if a display is connected)
    public var displayWidth: Int = 0
    public var displayHeight: Int = 0

    // A port is active if any data transport is running or something is
    // physically connected on the CC line (e.g. a charger).
    public var isActive: Bool {
        lane0.transport != .idle || lane1.transport != .idle || usb2Active || ccConnected
    }

    public var primaryProtocol: PortProtocol {
        if thunderboltLink != nil { return .thunderbolt }
        if lane0.transport == .displayPort || lane1.transport == .displayPort {
            return .displayPort
        }
        if lane0.transport == .usb || lane1.transport == .usb || usb2Active {
            return .usbOnly
        }
        if ccConnected {
            // MagSafe is charge-only: a connection is always a charger,
            // even when the battery is full and no live wattage is shown.
            if portType == .magSafe { return .charging }
            // USB-C: only a negotiated power contract makes it a charger.
            // A bare cable with nothing on the other end also trips the CC
            // line but carries no power and no data, so treat it as idle
            // rather than a phantom charger. Without this, an empty lead
            // reads as a charging port and inherits the system battery
            // state (e.g. "Battery Full").
            return power != nil ? .charging : .idle
        }
        return .idle
    }

    public init(
        id: Int,
        uuid: String? = nil,
        portType: PortType = .usbC,
        lane0: LaneState = .idle,
        lane1: LaneState = .idle,
        usb2Active: Bool = false,
        ccConnected: Bool = false,
        thunderboltLink: ThunderboltLinkState? = nil,
        power: PortPower? = nil,
        deviceName: String? = nil,
        usbSpeed: USBSpeed? = nil,
        usbDevice: USBDeviceInfo? = nil,
        cable: CableInfo? = nil,
        portStats: PortStatistics? = nil,
        thunderboltCapability: ThunderboltCapability? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.portType = portType
        self.lane0 = lane0
        self.lane1 = lane1
        self.usb2Active = usb2Active
        self.ccConnected = ccConnected
        self.thunderboltLink = thunderboltLink
        self.power = power
        self.deviceName = deviceName
        self.usbSpeed = usbSpeed
        self.usbDevice = usbDevice
        self.cable = cable
        self.portStats = portStats
        self.thunderboltCapability = thunderboltCapability
    }
}

// MARK: - Port Health

public enum HealthSeverity: Sendable, Equatable {
    case ok, warning, serious
}

// Health signals from the HPM port-controller node.
// Present only when the HPM layer is available (Apple Silicon, M1+).
public struct PortHealth: Sendable, Equatable {
    public var overcurrentCount: Int
    public var plugEventCount: Int
    public var connectionCount: Int
    public var authorizationStatus: String
    public var ldcmStatus: String

    // .serious when overcurrents have been recorded.
    // .warning when LDCM reports an error string.
    // .ok otherwise.
    public var severity: HealthSeverity {
        if overcurrentCount > 0 { return .serious }
        if !ldcmStatus.isEmpty && ldcmStatus != "No Error" { return .warning }
        return .ok
    }

    public var isHealthy: Bool { severity == .ok }

    public init(
        overcurrentCount: Int = 0,
        plugEventCount: Int = 0,
        connectionCount: Int = 0,
        authorizationStatus: String = "",
        ldcmStatus: String = ""
    ) {
        self.overcurrentCount = overcurrentCount
        self.plugEventCount = plugEventCount
        self.connectionCount = connectionCount
        self.authorizationStatus = authorizationStatus
        self.ldcmStatus = ldcmStatus
    }
}

// MARK: - Lane State

public struct LaneState: Sendable, Equatable {
    public var transport: LaneTransport
    public var powerLevel: PowerLevel
    public var client: String?

    public static let idle = LaneState(transport: .idle, powerLevel: .off, client: nil)

    public init(transport: LaneTransport, powerLevel: PowerLevel, client: String?) {
        self.transport = transport
        self.powerLevel = powerLevel
        self.client = client
    }
}

public enum LaneTransport: Sendable, Equatable {
    case thunderbolt
    case displayPort
    case usb
    case idle
}

public enum PowerLevel: Sendable, Equatable {
    case on
    case off
}

// MARK: - Thunderbolt Link

public struct ThunderboltLinkState: Sendable, Equatable {
    public var generation: TBGeneration
    public var perLaneGbps: Int
    public var txLanes: Int
    public var rxLanes: Int
    public var totalGbps: Int
    public var deviceName: String?
    public var deviceVendor: String?

    public init(
        generation: TBGeneration,
        perLaneGbps: Int,
        txLanes: Int,
        rxLanes: Int,
        deviceName: String? = nil,
        deviceVendor: String? = nil
    ) {
        self.generation = generation
        self.perLaneGbps = perLaneGbps
        self.txLanes = txLanes
        self.rxLanes = rxLanes
        self.totalGbps = perLaneGbps * txLanes
        self.deviceName = deviceName
        self.deviceVendor = deviceVendor
    }
}

public enum TBGeneration: Sendable, Equatable {
    case tb3
    case tb4
    case tb5

    // Maps IOKit "Current Link Speed" register values to generation.
    // Lower value = faster. From thunderbolt-fabric.md research:
    // 0x2 = Gen 4 / TB5 (40 Gbps/lane)
    // 0x4 = Gen 3 / TB4 (20 Gbps/lane)
    // 0x8 = Gen 2 / TB3 (10 Gbps/lane)
    //
    // This is for "Current Link Speed" only, which is always a single code.
    // For "Supported Link Speed" (a bitmask) use init(supportedSpeedMask:),
    // and for static port capability prefer init(thunderboltVersion:).
    public init(speedCode: Int) {
        switch speedCode {
        case 0x2: self = .tb5
        case 0x4: self = .tb4
        case 0x8: self = .tb3
        default: self = .tb4
        }
    }

    // Maps the IOKit "Thunderbolt Version" controller constant to generation.
    // From thunderbolt-fabric.md research:
    // 64 = Type7 (TB5), 32 = Type5 (TB4), 16 = Intel Type3/Type4 (TB3)
    // This is the most stable capability signal: it is present even when the
    // port is idle, unlike the negotiated link/supported-speed fields.
    // Returns nil for unknown values so callers can fall back.
    public init?(thunderboltVersion: Int) {
        switch thunderboltVersion {
        case 64: self = .tb5
        case 32: self = .tb4
        case 16: self = .tb3
        default: return nil
        }
    }

    // Maps the IOKit "Supported Link Speed" bitmask to the highest generation.
    // Unlike "Current Link Speed", this field ORs together every speed the
    // controller supports (e.g. 0x4 | 0x8 = 12 for a TB4 controller,
    // 0x2 | 0x4 | 0x8 = 14 for TB5). We pick the fastest bit that is set.
    // Returns nil when no known bit is set so callers can fall back.
    public init?(supportedSpeedMask: Int) {
        if supportedSpeedMask & 0x2 != 0 { self = .tb5 }
        else if supportedSpeedMask & 0x4 != 0 { self = .tb4 }
        else if supportedSpeedMask & 0x8 != 0 { self = .tb3 }
        else { return nil }
    }

    public var label: String {
        switch self {
        case .tb3: return "TB3"
        case .tb4: return "TB4"
        case .tb5: return "TB5"
        }
    }

    public var perLaneGbps: Int {
        switch self {
        case .tb3: return 10
        case .tb4: return 20
        case .tb5: return 40
        }
    }
}

// MARK: - Port Power

public struct PortPower: Sendable, Equatable {
    public var watts: Double
    public var current: Int
    public var voltage: Int
    public var configuredVoltage: Int
    public var configuredCurrent: Int
    public var vconnCurrent: Int

    public init(
        watts: Double,
        current: Int,
        voltage: Int,
        configuredVoltage: Int,
        configuredCurrent: Int,
        vconnCurrent: Int
    ) {
        self.watts = watts
        self.current = current
        self.voltage = voltage
        self.configuredVoltage = configuredVoltage
        self.configuredCurrent = configuredCurrent
        self.vconnCurrent = vconnCurrent
    }
}

// MARK: - Port Type (physical connector)

public enum PortType: Sendable, Equatable {
    case usbC
    case magSafe

    public var label: String {
        switch self {
        case .usbC: return "USB-C"
        case .magSafe: return "MagSafe"
        }
    }
}

// MARK: - USB Speed

public enum USBSpeed: Sendable, Equatable {
    case lowSpeed       // 1.5 Mbps
    case fullSpeed      // 12 Mbps
    case highSpeed      // 480 Mbps (USB 2.0)
    case superSpeed     // 5 Gbps (USB 3.0)
    case superSpeedPlus // 10 Gbps (USB 3.2 Gen 2)
    case superSpeed2x2  // 20 Gbps (USB 3.2 Gen 2x2)

    public init(code: Int) {
        switch code {
        case 0: self = .lowSpeed
        case 1: self = .fullSpeed
        case 2: self = .highSpeed
        case 3: self = .superSpeed
        case 4: self = .superSpeedPlus
        case 5: self = .superSpeed2x2
        default: self = .fullSpeed
        }
    }

    public var label: String {
        switch self {
        case .lowSpeed: return "1.5 Mbps"
        case .fullSpeed: return "12 Mbps"
        case .highSpeed: return "480 Mbps"
        case .superSpeed: return "5 Gbps"
        case .superSpeedPlus: return "10 Gbps"
        case .superSpeed2x2: return "20 Gbps"
        }
    }
}

// MARK: - USB Device Info

public struct USBDeviceInfo: Sendable, Equatable {
    public var productName: String
    public var vendorName: String
    public var serialNumber: String?
    public var speed: USBSpeed?
    public var usbVersion: String    // "USB 3.2", "USB 2.0", etc.
    public var currentDraw: Int      // mA allocated by host

    public init(
        productName: String,
        vendorName: String,
        serialNumber: String? = nil,
        speed: USBSpeed? = nil,
        usbVersion: String = "",
        currentDraw: Int = 0
    ) {
        self.productName = productName
        self.vendorName = vendorName
        self.serialNumber = serialNumber
        self.speed = speed
        self.usbVersion = usbVersion
        self.currentDraw = currentDraw
    }
}

// MARK: - Cable Info

public struct CableInfo: Sendable, Equatable {
    public var productType: String   // "Passive Cable", "Active Cable"
    public var pdRevision: Int       // USB PD Specification Revision (1, 2, 3)

    public init(productType: String, pdRevision: Int = 0) {
        self.productType = productType
        self.pdRevision = pdRevision
    }
}

// MARK: - Port Statistics

public struct PortStatistics: Sendable, Equatable {
    public var connectCount: Int
    public var overcurrentCount: Int
    public var enumerationFailureCount: Int
    public var addressFailureCount: Int
    public var linkErrorCount: Int
    public var remoteWakeCount: Int

    public init(
        connectCount: Int = 0,
        overcurrentCount: Int = 0,
        enumerationFailureCount: Int = 0,
        addressFailureCount: Int = 0,
        linkErrorCount: Int = 0,
        remoteWakeCount: Int = 0
    ) {
        self.connectCount = connectCount
        self.overcurrentCount = overcurrentCount
        self.enumerationFailureCount = enumerationFailureCount
        self.addressFailureCount = addressFailureCount
        self.linkErrorCount = linkErrorCount
        self.remoteWakeCount = remoteWakeCount
    }
}

// MARK: - Thunderbolt Capability

// Port-level TB capability (always present for TB-capable ports,
// even when no device is connected and no link is active).
public struct ThunderboltCapability: Sendable, Equatable {
    public var supportedLinkSpeed: Int   // speed bitmask (12 = TB4, 14 = TB5)
    public var supportedLinkWidth: Int   // max width code (2 = dual-lane)
    public var thunderboltVersion: Int

    // Prefer the static "Thunderbolt Version" constant: it reports the
    // controller's true ceiling even when the port is idle. Fall back to the
    // supported-speed bitmask, then to TB4 as a last resort.
    public var maxGeneration: TBGeneration {
        TBGeneration(thunderboltVersion: thunderboltVersion)
            ?? TBGeneration(supportedSpeedMask: supportedLinkSpeed)
            ?? .tb4
    }

    // "Supported Link Width" is a bitmask: BIT(0)=0x1 single-lane, BIT(1)=0x2
    // dual-lane. A TB5 port reports 3 (0x1|0x2), meaning it supports both.
    // Pick the highest width bit that is set, same approach as init(supportedSpeedMask:).
    public var maxLanes: Int {
        if supportedLinkWidth & 0x2 != 0 { return 2 }
        return 1
    }

    public init(
        supportedLinkSpeed: Int = 0,
        supportedLinkWidth: Int = 0,
        thunderboltVersion: Int = 0
    ) {
        self.supportedLinkSpeed = supportedLinkSpeed
        self.supportedLinkWidth = supportedLinkWidth
        self.thunderboltVersion = thunderboltVersion
    }
}

// MARK: - Live Transport State

// Real-time link data from IOPortTransportState* services.
// One per active transport on a port. Updated on every snapshot.
public struct LiveTransport: Sendable, Equatable {
    public var kind: LaneTransport       // .usb, .displayPort, .thunderbolt
    public var dataRate: String          // "10 Gbps", "5.4 Gbps (HBR2)"
    public var generation: String        // "Gen 2", "USB 3.x" (USB only)
    public var laneCount: Int            // DP only; 0 otherwise
    public var maxLaneCount: Int         // DP only
    public var tunneled: Bool
    // macOS Transport Restriction Mode has blocked data on this link.
    // The link still reports a signaling speed, but no data flows until the
    // device is authorised. Surface this so a blocked port is not mistaken
    // for a healthy one. USB only; always false for DP/Thunderbolt.
    public var restricted: Bool

    public init(
        kind: LaneTransport,
        dataRate: String = "",
        generation: String = "",
        laneCount: Int = 0,
        maxLaneCount: Int = 0,
        tunneled: Bool = false,
        restricted: Bool = false
    ) {
        self.kind = kind
        self.dataRate = dataRate
        self.generation = generation
        self.laneCount = laneCount
        self.maxLaneCount = maxLaneCount
        self.tunneled = tunneled
        self.restricted = restricted
    }
}

// MARK: - Protocol Classification

public enum PortProtocol: Sendable, Equatable, Codable {
    case thunderbolt
    case displayPort
    case usbOnly
    case charging
    case idle
}
