import WhatPortCore
import WhatPortIOKit

// Converts IOKit's raw PortSnapshot into the domain layer's PortManagerSnapshot.
// This adapter sits in the app target because it bridges the two library targets.
// Neither library imports the other directly.
enum SnapshotAdapter {
    static func convert(_ snapshot: PortSnapshot) -> PortManagerSnapshot {
        PortManagerSnapshot(
            timestamp: snapshot.timestamp,
            phyData: snapshot.phyData.map { phy in
                PhyInput(
                    phyID: phy.phyID,
                    lane0Transport: phy.lane0Transport,
                    lane0PowerLevel: phy.lane0PowerLevel,
                    lane0Client: phy.lane0Client,
                    lane1Transport: phy.lane1Transport,
                    lane1PowerLevel: phy.lane1PowerLevel,
                    lane1Client: phy.lane1Client,
                    usb2Transport: phy.usb2Transport
                )
            },
            tbData: snapshot.thunderboltData.compactMap { tb in
                guard let socketID = Int(tb.socketID) else { return nil }
                return ThunderboltInput(
                    socketID: socketID,
                    currentLinkWidth: tb.currentLinkWidth,
                    currentLinkSpeed: tb.currentLinkSpeed,
                    dualLinkPort: tb.dualLinkPort
                )
            },
            powerData: snapshot.powerData.map { pwr in
                PowerInput(
                    portIndex: pwr.portIndex,
                    watts: pwr.watts,
                    current: pwr.current,
                    adapterVoltage: pwr.adapterVoltage,
                    configuredVoltage: pwr.configuredVoltage,
                    configuredCurrent: pwr.configuredCurrent,
                    vconnCurrent: pwr.vconnCurrent
                )
            },
            ccData: snapshot.ccData.map { cc in
                CCInput(portNumber: cc.portNumber, active: cc.active)
            },
            powerMeteringAvailable: snapshot.powerMeteringAvailable
        )
    }
}
