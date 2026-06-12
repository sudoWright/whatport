import Testing
@testable import WhatPortIOKit

// Smoke tests that read from real IOKit on this machine.
// These verify the readers don't crash and return plausible data.

@Test func phyReaderFindsAtLeastOnePort() {
    let phys = PhyReader.readAll()
    #expect(!phys.isEmpty, "Expected at least one AppleTypeCPhy instance on Apple Silicon")
}

@Test func phyReaderReturnsSortedByID() {
    let phys = PhyReader.readAll()
    let ids = phys.map(\.phyID)
    #expect(ids == ids.sorted())
}

@Test func thunderboltReaderFindsPhysicalPorts() {
    let ports = ThunderboltReader.readAll()
    #expect(!ports.isEmpty, "Expected at least one IOThunderboltPort with Socket ID")

    for port in ports {
        #expect(!port.socketID.isEmpty, "Socket ID should not be empty")
    }
}

@Test func hpmReaderFindsPortsWithUUIDs() {
    let ports = HPMReader.readAll()
    #expect(!ports.isEmpty, "Expected at least one HPM port-controller node on Apple Silicon")

    for port in ports {
        #expect(!port.uuid.isEmpty, "Each HPM port should carry a UUID")
        #expect(port.portNumber > 0, "Each HPM port should have a positive port number")
    }

    // UUIDs must be unique per physical port, even when MagSafe and USB-C
    // share the same "@N" number (the whole point of using them).
    let uuids = ports.map(\.uuid)
    #expect(Set(uuids).count == uuids.count, "HPM port UUIDs should be unique")
}

@Test func snapshotReaderProducesCompleteSnapshot() {
    let snapshot = SnapshotReader.takeSnapshot()
    #expect(!snapshot.phyData.isEmpty)
    #expect(!snapshot.thunderboltData.isEmpty)
    #expect(!snapshot.hpmPorts.isEmpty)
}
