import Testing
@testable import WhatPortCore

@Test func portManagerAppliesSnapshotWithIdlePorts() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [
            PhyInput(phyID: 0),
            PhyInput(phyID: 1),
            PhyInput(phyID: 2)
        ],
        tbData: [
            ThunderboltInput(socketID: 1),
            ThunderboltInput(socketID: 2),
            ThunderboltInput(socketID: 4)
        ]
    )

    manager.applySnapshot(snapshot)

    #expect(manager.ports.count == 3)
    #expect(manager.portCount == 3)
    #expect(manager.activePortCount == 0)
    #expect(manager.ports[0].id == 1)
    #expect(manager.ports[1].id == 2)
    #expect(manager.ports[2].id == 4)
}

@Test func portManagerCorrelatesTBActivePort() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [
            PhyInput(phyID: 0, lane0Transport: "CIO", lane0PowerLevel: "on", lane1Transport: "CIO", lane1PowerLevel: "on"),
            PhyInput(phyID: 1),
            PhyInput(phyID: 2)
        ],
        tbData: [
            ThunderboltInput(socketID: 1, currentLinkWidth: 2, currentLinkSpeed: 4),
            ThunderboltInput(socketID: 2),
            ThunderboltInput(socketID: 4)
        ]
    )

    manager.applySnapshot(snapshot)

    let port1 = manager.ports[0]
    #expect(port1.isActive)
    #expect(port1.lane0.transport == .thunderbolt)
    #expect(port1.lane1.transport == .thunderbolt)
    #expect(port1.thunderboltLink != nil)
    #expect(port1.thunderboltLink?.generation == .tb4)
    #expect(port1.thunderboltLink?.perLaneGbps == 20)
    #expect(port1.thunderboltLink?.txLanes == 2)
    #expect(port1.thunderboltLink?.totalGbps == 40)
}

@Test func portManagerCorrelatesPowerData() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [PhyInput(phyID: 0)],
        tbData: [ThunderboltInput(socketID: 1)],
        powerData: [
            PowerInput(
                portIndex: 1,
                watts: 5900,
                current: 113,
                adapterVoltage: 5200,
                configuredVoltage: 5000,
                configuredCurrent: 1500,
                vconnCurrent: 14
            )
        ],
        powerMeteringAvailable: true
    )

    manager.applySnapshot(snapshot)

    let port = manager.ports[0]
    #expect(port.power != nil)
    #expect(port.power?.watts == 5.9)
    #expect(port.power?.current == 113)
    #expect(port.power?.voltage == 5200)
    #expect(manager.powerMeteringAvailable)
}

@Test func portManagerTracksPowerHistory() {
    let manager = PortManager()

    for i in 0..<25 {
        let snapshot = PortManagerSnapshot(
            phyData: [PhyInput(phyID: 0)],
            tbData: [ThunderboltInput(socketID: 1)],
            powerData: [PowerInput(portIndex: 1, watts: i * 1000)]
        )
        manager.applySnapshot(snapshot)
    }

    let history = manager.powerHistory[1] ?? []
    #expect(history.count == 20) // capped at maxPowerSamples
    #expect(history.last?.watts == 24.0) // last sample: 24000 mW = 24.0W
}

@Test func portManagerDeduplicatesTBAdapters() {
    let manager = PortManager()

    // Two TB adapters for same socket (one per lane), different widths
    let snapshot = PortManagerSnapshot(
        phyData: [PhyInput(phyID: 0)],
        tbData: [
            ThunderboltInput(socketID: 1, currentLinkWidth: 1, currentLinkSpeed: 4),
            ThunderboltInput(socketID: 1, currentLinkWidth: 2, currentLinkSpeed: 4)
        ]
    )

    manager.applySnapshot(snapshot)

    #expect(manager.ports.count == 1)
    #expect(manager.ports[0].thunderboltLink?.txLanes == 2) // picked the wider one
}

// Mirrors real M4 Pro hardware: 4 PHYs, 3 ports.
// PHY 0 and PHY 2 both map to port 1. PHY 2 is idle, PHY 0 is active.
// Without direct mapping, positional logic would wrongly assign PHY 2 to port 4.
@Test func portManagerUsesDirectPhyToPortMapping() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [
            PhyInput(phyID: 0, portNumber: 1, lane0Transport: "USB3", lane0PowerLevel: "on"),
            PhyInput(phyID: 1, portNumber: 2, lane0Transport: "DisplayPort", lane0PowerLevel: "on"),
            PhyInput(phyID: 2, portNumber: 1), // duplicate port 1, idle
            PhyInput(phyID: 3, portNumber: 4)
        ],
        tbData: [
            ThunderboltInput(socketID: 1),
            ThunderboltInput(socketID: 2),
            ThunderboltInput(socketID: 4)
        ]
    )

    manager.applySnapshot(snapshot)

    // Should have 3 ports (from TB socket IDs), not 4
    #expect(manager.ports.count == 3)

    // Port 1: should get PHY 0's USB3 data (active wins over PHY 2's idle)
    let port1 = manager.ports[0]
    #expect(port1.id == 1)
    #expect(port1.lane0.transport == .usb)

    // Port 2: should get PHY 1's DisplayPort data
    let port2 = manager.ports[1]
    #expect(port2.id == 2)
    #expect(port2.lane0.transport == .displayPort)

    // Port 4: should get PHY 3's idle data (not PHY 2)
    let port3 = manager.ports[2]
    #expect(port3.id == 4)
    #expect(!port3.isActive)
}

// When port-number is not available (0), fall back to positional mapping.
// This is the legacy behavior for machines where device tree doesn't
// expose port-number on atc-phy nodes.
@Test func portManagerFallsBackToPositionalMapping() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [
            PhyInput(phyID: 0, lane0Transport: "CIO", lane0PowerLevel: "on"),
            PhyInput(phyID: 1)
        ],
        tbData: [
            ThunderboltInput(socketID: 1, currentLinkWidth: 2, currentLinkSpeed: 4),
            ThunderboltInput(socketID: 2)
        ]
    )

    manager.applySnapshot(snapshot)

    #expect(manager.ports.count == 2)
    // Positional: PHY 0 -> socket 1, PHY 1 -> socket 2
    #expect(manager.ports[0].id == 1)
    #expect(manager.ports[0].lane0.transport == .thunderbolt)
    #expect(manager.ports[1].id == 2)
    #expect(!manager.ports[1].isActive)
}

// When duplicate PHYs map to the same port, the one with active transport
// should be selected, regardless of phyID order.
@Test func portManagerDedupPicksActivePhy() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [
            PhyInput(phyID: 0, portNumber: 1), // idle
            PhyInput(phyID: 2, portNumber: 1, lane0Transport: "CIO", lane0PowerLevel: "on") // active
        ],
        tbData: [
            ThunderboltInput(socketID: 1, currentLinkWidth: 2, currentLinkSpeed: 4)
        ]
    )

    manager.applySnapshot(snapshot)

    #expect(manager.ports.count == 1)
    #expect(manager.ports[0].lane0.transport == .thunderbolt) // got the active PHY
}

// MagSafe and USB-C port 1 share ParentBuiltInPortNumber = 1.
// MagSafe must not pollute USB-C port state, and should appear as its own entry.
@Test func portManagerSeparatesMagSafeFromUSBC() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [
            PhyInput(phyID: 0, portNumber: 1),
            PhyInput(phyID: 1, portNumber: 2)
        ],
        tbData: [
            ThunderboltInput(socketID: 1),
            ThunderboltInput(socketID: 2)
        ],
        ccData: [
            CCInput(portNumber: 1, portType: "USB-C", active: false),
            CCInput(portNumber: 2, portType: "USB-C", active: true),
            CCInput(portNumber: 1, portType: "MagSafe 3", active: true)
        ]
    )

    manager.applySnapshot(snapshot)

    // 2 USB-C ports + 1 MagSafe = 3 total
    #expect(manager.ports.count == 3)

    // USB-C port 1: CC inactive (not contaminated by MagSafe)
    let usbcPort1 = manager.ports[0]
    #expect(usbcPort1.id == 1)
    #expect(usbcPort1.portType == .usbC)
    #expect(!usbcPort1.ccConnected)
    #expect(!usbcPort1.isActive)

    // USB-C port 2: CC active
    let usbcPort2 = manager.ports[1]
    #expect(usbcPort2.id == 2)
    #expect(usbcPort2.ccConnected)

    // MagSafe: shown as its own port, active
    let magSafe = manager.ports[2]
    #expect(magSafe.portType == .magSafe)
    #expect(magSafe.ccConnected)
    #expect(magSafe.isActive)
    #expect(magSafe.primaryProtocol == .charging)
}

// The headline win of HPM-anchored correlation: USB-C@1 and MagSafe@1 share
// the same "@N" number but get distinct stable UUIDs, so data can never bleed
// between them. UUIDs taken from a real M5 MacBook Pro.
@Test func portManagerStampsDistinctUUIDsForCollidingPortNumbers() {
    let manager = PortManager()

    let usbc1UUID = "6230AF2D-EE59-552E-E28A-652CCC0E7B11"
    let usbc2UUID = "492BAF2D-4561-2E29-5FFE-BD2ADE023D0F"
    let magSafeUUID = "7C30AF2D-CC71-7D20-5287-C77DB8476817"

    let snapshot = PortManagerSnapshot(
        hpmPorts: [
            HPMPortInput(uuid: usbc1UUID, portNumber: 1, portType: "USB-C"),
            HPMPortInput(uuid: usbc2UUID, portNumber: 2, portType: "USB-C"),
            HPMPortInput(uuid: magSafeUUID, portNumber: 1, portType: "MagSafe 3"),
        ],
        phyData: [
            PhyInput(phyID: 0, portNumber: 1),
            PhyInput(phyID: 1, portNumber: 2),
        ],
        tbData: [
            ThunderboltInput(socketID: 1),
            ThunderboltInput(socketID: 2),
        ],
        ccData: [
            CCInput(portNumber: 1, portType: "USB-C", active: false),
            CCInput(portNumber: 2, portType: "USB-C", active: true),
            CCInput(portNumber: 1, portType: "MagSafe 3", active: true),
        ]
    )

    manager.applySnapshot(snapshot)

    let usbc1 = manager.ports.first { $0.id == 1 && $0.portType == .usbC }
    let magSafe = manager.ports.first { $0.portType == .magSafe }

    #expect(usbc1?.uuid == usbc1UUID)
    #expect(magSafe?.uuid == magSafeUUID)
    // Same @N = 1, different physical port, different identity.
    #expect(usbc1?.uuid != magSafe?.uuid)
}

// Without HPM data (Intel / desktop / tests), ports still correlate by number
// and simply carry no UUID. Confirms the legacy fallback path is intact.
@Test func portManagerCorrelatesWithoutHPMData() {
    let manager = PortManager()

    let snapshot = PortManagerSnapshot(
        phyData: [PhyInput(phyID: 0, portNumber: 1)],
        tbData: [ThunderboltInput(socketID: 1)],
        ccData: [CCInput(portNumber: 1, portType: "USB-C", active: true)]
    )

    manager.applySnapshot(snapshot)

    #expect(manager.ports.count == 1)
    #expect(manager.ports[0].id == 1)
    #expect(manager.ports[0].uuid == nil)
}
