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

@Test func snapshotReaderProducesCompleteSnapshot() {
    let snapshot = SnapshotReader.takeSnapshot()
    #expect(!snapshot.phyData.isEmpty)
    #expect(!snapshot.thunderboltData.isEmpty)
}
