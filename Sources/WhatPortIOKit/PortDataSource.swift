import Foundation
import WhatPortCore

// The contract between IOKit and domain layers.
// The domain layer depends on this protocol, never on concrete IOKit calls.

public protocol PortDataSource: Sendable {
    func observePortUpdates() -> AsyncStream<PortSnapshot>
    func start() async
    func stop()
}

// A complete, immutable snapshot of all port state at a point in time.
// The IOKit layer produces one of these on every notification or poll tick.
public struct PortSnapshot: Sendable {
    public let timestamp: Date
    public let phyData: [RawPhyData]
    public let thunderboltData: [RawThunderboltData]
    public let powerData: [RawPowerData]
    public let ccData: [RawCCData]
    public let chargerData: [RawChargerData]
    public let chargingPower: RawChargingPower?
    public let deviceData: [RawDeviceInfo]
    public let displayData: [RawDisplayInfo]
    public let portStatsData: [RawPortStats]
    public let powerMeteringAvailable: Bool

    public init(
        timestamp: Date = .now,
        phyData: [RawPhyData] = [],
        thunderboltData: [RawThunderboltData] = [],
        powerData: [RawPowerData] = [],
        ccData: [RawCCData] = [],
        chargerData: [RawChargerData] = [],
        chargingPower: RawChargingPower? = nil,
        deviceData: [RawDeviceInfo] = [],
        displayData: [RawDisplayInfo] = [],
        portStatsData: [RawPortStats] = [],
        powerMeteringAvailable: Bool = false
    ) {
        self.timestamp = timestamp
        self.phyData = phyData
        self.thunderboltData = thunderboltData
        self.powerData = powerData
        self.ccData = ccData
        self.chargerData = chargerData
        self.chargingPower = chargingPower
        self.deviceData = deviceData
        self.displayData = displayData
        self.portStatsData = portStatsData
        self.powerMeteringAvailable = powerMeteringAvailable
    }
}

// One-shot reader that produces a single snapshot from current IOKit state.
// Used for initial load and on-demand refresh. Notifications and polling
// are added in Chunk 4.
public enum SnapshotReader {
    public static func takeSnapshot() -> PortSnapshot {
        PortSnapshot(
            timestamp: .now,
            phyData: PhyReader.readAll(),
            thunderboltData: ThunderboltReader.readAll(),
            powerData: PowerReader.readAll(),
            ccData: CCReader.readAll(),
            chargerData: ChargerReader.readAll(),
            chargingPower: PowerReader.readChargingPower(),
            deviceData: DeviceReader.readUSBDevices(),
            displayData: DisplayReader.readDisplays(),
            portStatsData: PortStatsReader.readAll(),
            powerMeteringAvailable: PowerReader.isPowerMeteringAvailable()
        )
    }
}
