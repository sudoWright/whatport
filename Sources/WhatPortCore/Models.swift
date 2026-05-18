import Foundation

// All domain model types for WhatPort.
// These are pure value types with no IOKit or UI dependencies.

// MARK: - Port State

public struct PortState: Identifiable, Sendable {
    public let id: Int
    public var portType: PortType
    public var lane0: LaneState
    public var lane1: LaneState
    public var usb2Active: Bool
    public var ccConnected: Bool
    public var thunderboltLink: ThunderboltLinkState?
    public var power: PortPower?
    public var deviceName: String?

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
        // CC connected but no data lanes = power-only (charger/MagSafe)
        if ccConnected { return .charging }
        return .idle
    }

    public init(
        id: Int,
        portType: PortType = .usbC,
        lane0: LaneState = .idle,
        lane1: LaneState = .idle,
        usb2Active: Bool = false,
        ccConnected: Bool = false,
        thunderboltLink: ThunderboltLinkState? = nil,
        power: PortPower? = nil,
        deviceName: String? = nil
    ) {
        self.id = id
        self.portType = portType
        self.lane0 = lane0
        self.lane1 = lane1
        self.usb2Active = usb2Active
        self.ccConnected = ccConnected
        self.thunderboltLink = thunderboltLink
        self.power = power
        self.deviceName = deviceName
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
    public init(speedCode: Int) {
        switch speedCode {
        case 0x2: self = .tb5
        case 0x4: self = .tb4
        case 0x8: self = .tb3
        default: self = .tb4
        }
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

// MARK: - Protocol Classification

public enum PortProtocol: Sendable, Equatable {
    case thunderbolt
    case displayPort
    case usbOnly
    case charging
    case idle
}
