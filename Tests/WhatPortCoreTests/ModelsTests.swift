import Testing
@testable import WhatPortCore

@Test func laneTransportEnumExists() {
    let transport: LaneTransport = .thunderbolt
    #expect(transport == .thunderbolt)
}

@Test func tbGenerationFromSpeedCode() {
    #expect(TBGeneration(speedCode: 0x8) == .tb3)
    #expect(TBGeneration(speedCode: 4) == .tb4)
    #expect(TBGeneration(speedCode: 12) == .tb5)
    #expect(TBGeneration(speedCode: 99) == .tb4) // unknown defaults to TB4
}

@Test func tbGenerationPerLaneSpeed() {
    #expect(TBGeneration.tb3.perLaneGbps == 10)
    #expect(TBGeneration.tb4.perLaneGbps == 20)
    #expect(TBGeneration.tb5.perLaneGbps == 40)
}

@Test func portStateIsActiveWhenLaneHasTransport() {
    var port = PortState(id: 1)
    #expect(!port.isActive)

    port.lane0 = LaneState(transport: .thunderbolt, powerLevel: .on, client: nil)
    #expect(port.isActive)
}

@Test func portStatePrimaryProtocol() {
    let idle = PortState(id: 1)
    #expect(idle.primaryProtocol == .idle)

    let tb = PortState(
        id: 2,
        lane0: LaneState(transport: .thunderbolt, powerLevel: .on, client: nil),
        thunderboltLink: ThunderboltLinkState(generation: .tb4, perLaneGbps: 20, txLanes: 2, rxLanes: 2)
    )
    #expect(tb.primaryProtocol == .thunderbolt)

    let dp = PortState(
        id: 3,
        lane0: LaneState(transport: .displayPort, powerLevel: .on, client: nil),
        lane1: LaneState(transport: .displayPort, powerLevel: .on, client: nil)
    )
    #expect(dp.primaryProtocol == .displayPort)
}
