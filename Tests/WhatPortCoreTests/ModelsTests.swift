import Testing
@testable import WhatPortCore

@Test func laneTransportEnumExists() {
    let transport: LaneTransport = .thunderbolt
    #expect(transport == .thunderbolt)
}

@Test func tbGenerationFromSpeedCode() {
    #expect(TBGeneration(speedCode: 0x8) == .tb3)
    #expect(TBGeneration(speedCode: 0x4) == .tb4)
    #expect(TBGeneration(speedCode: 0x2) == .tb5)
    #expect(TBGeneration(speedCode: 99) == .tb4) // unknown defaults to TB4
}

@Test func tbGenerationFromThunderboltVersion() {
    #expect(TBGeneration(thunderboltVersion: 16) == .tb3)
    #expect(TBGeneration(thunderboltVersion: 32) == .tb4)
    #expect(TBGeneration(thunderboltVersion: 64) == .tb5)
    #expect(TBGeneration(thunderboltVersion: 0) == nil) // unknown -> nil
}

@Test func tbGenerationFromSupportedSpeedMask() {
    #expect(TBGeneration(supportedSpeedMask: 0x8) == .tb3)        // TB3 only
    #expect(TBGeneration(supportedSpeedMask: 12) == .tb4)         // 0x4|0x8
    #expect(TBGeneration(supportedSpeedMask: 14) == .tb5)         // 0x2|0x4|0x8
    #expect(TBGeneration(supportedSpeedMask: 0) == nil)           // nothing set
}

// Regression: a TB5 host (Thunderbolt Version 64) whose supported-speed
// bitmask reads 12 must report TB5 capability, not TB4. Previously the
// bitmask was fed into the per-lane speed-code decoder and fell through
// to the TB4 default.
@Test func tbCapabilityReportsTB5OnTB5Host() {
    let cap = ThunderboltCapability(
        supportedLinkSpeed: 12,
        supportedLinkWidth: 0x2,
        thunderboltVersion: 64
    )
    #expect(cap.maxGeneration == .tb5)
}

@Test func tbCapabilityFallsBackToMaskWhenVersionUnknown() {
    let cap = ThunderboltCapability(
        supportedLinkSpeed: 14,
        supportedLinkWidth: 0x2,
        thunderboltVersion: 0
    )
    #expect(cap.maxGeneration == .tb5)
}

// Regression: supportedLinkWidth is a bitmask. TB5 reports 3 (0x1|0x2) which
// previously fell through to the default and wrongly returned 1 (single-lane).
@Test func tbCapabilityMaxLanesBitmask() {
    let dualCap = ThunderboltCapability(supportedLinkSpeed: 14, supportedLinkWidth: 3, thunderboltVersion: 64)
    #expect(dualCap.maxLanes == 2)

    let singleCap = ThunderboltCapability(supportedLinkSpeed: 14, supportedLinkWidth: 1, thunderboltVersion: 64)
    #expect(singleCap.maxLanes == 1)
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

@Test func portHealthSeverityOk() {
    let health = PortHealth(overcurrentCount: 0, ldcmStatus: "No Error")
    #expect(health.severity == .ok)
    #expect(health.isHealthy == true)
}

@Test func portHealthSeverityOkEmptyLdcm() {
    let health = PortHealth(overcurrentCount: 0, ldcmStatus: "")
    #expect(health.severity == .ok)
    #expect(health.isHealthy == true)
}

@Test func portHealthSeverityWarning() {
    let health = PortHealth(overcurrentCount: 0, ldcmStatus: "Some Error")
    #expect(health.severity == .warning)
    #expect(health.isHealthy == false)
}

@Test func portHealthSeveritySeriousOvercurrent() {
    let health = PortHealth(overcurrentCount: 1, ldcmStatus: "No Error")
    #expect(health.severity == .serious)
    #expect(health.isHealthy == false)
}

@Test func portHealthSeverityOvercurrentDominates() {
    // Overcurrent takes priority over a warning-level LDCM status
    let health = PortHealth(overcurrentCount: 2, ldcmStatus: "Some Error")
    #expect(health.severity == .serious)
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
