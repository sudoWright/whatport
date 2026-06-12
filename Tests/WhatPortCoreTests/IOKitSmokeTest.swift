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

@Test func smcDecodeFloatHandlesFiniteAndGarbage() {
    // 5.0f little-endian = 0x40A00000 -> bytes 00 00 A0 40
    #expect(SMCPowerReader.decodeFloat([0x00, 0x00, 0xA0, 0x40]) == 5.0)
    // Short payloads and non-finite bit patterns return nil.
    #expect(SMCPowerReader.decodeFloat([0x00, 0x00]) == nil)
    #expect(SMCPowerReader.decodeFloat([0x00, 0x00, 0x80, 0x7F]) == nil) // +inf
    #expect(SMCPowerReader.decodeFloat([0x00, 0x00, 0xC0, 0x7F]) == nil) // NaN
}

@Test func smcFourCCPacksKey() {
    // "D3UI" -> 0x44 33 55 49
    #expect(SMCPowerReader.fourCC("D3UI") == 0x44335549)
    #expect(SMCPowerReader.fourCC("TOOLONG") == nil)
}

@Test func smcReaderReadsPortChannelsWithUUIDs() {
    let channels = SMCPowerReader().readPortPowerChannels()
    // Apple Silicon exposes D1..D4 power channels with a DxUI per channel.
    #expect(!channels.isEmpty, "Expected SMC port-power channels on Apple Silicon")
    for channel in channels {
        #expect(channel.uuid.count == 32, "DxUI should be 32 hex chars")
        #expect(channel.uuid == channel.uuid.lowercased())
    }
    // Each channel's UUID must be unique (one per physical port).
    let uuids = channels.map(\.uuid)
    #expect(Set(uuids).count == uuids.count)
}
