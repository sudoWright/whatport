import Foundation

// Protocol for the port recording engine.
//
// PortManager calls recordSnapshot() on every poll cycle. The concrete
// FlightRecorder implementation lives in WhatPortPlugins (Pro code).
// When no plugin registers a recorder, PortManager.recorder stays nil
// and the optional-chain call is a no-op.
//
// This protocol lives in WhatPortCore so neither PortManager nor the
// host app need to import the Pro module directly.

public protocol PortRecorder: AnyObject, Sendable {
    func recordSnapshot(ports: [PortState], timestamp: Date)

    // Acknowledged lifetime fault counters for a port, if the recorder tracks them.
    // Lets the host app (which only sees `any PortRecorder`) reflect a user's
    // "Reset Health Counters" action in its own UI without importing the Pro module.
    // Defaults to nil, so recorders that don't support it (and the OSS build, which
    // has no recorder) simply see no acknowledgement.
    func acknowledgedCounters(forPort portID: Int) -> AcknowledgedCounters?
}

public extension PortRecorder {
    func acknowledgedCounters(forPort portID: Int) -> AcknowledgedCounters? { nil }
}

// A snapshot of a port's lifetime fault counters at the moment the user chose to
// "acknowledge" them in settings. The health scorer subtracts these, so
// previously-seen counts no longer affect the score and only NEW faults above the
// acknowledged level count. The Mac's port-controller counters are read-only (we
// can't zero them), so this per-user baseline is the honest equivalent of a reset.
//
// Lives here (shared) rather than with the scorer so the host app and the
// PortRecorder seam can name it without depending on the Pro-only scoring code.
public struct AcknowledgedCounters: Sendable, Equatable, Codable {
    public let overcurrentCount: Int
    public let linkErrorCount: Int
    public let enumerationFailureCount: Int
    public let addressFailureCount: Int
    public let ldcmStatus: String

    public init(
        overcurrentCount: Int = 0,
        linkErrorCount: Int = 0,
        enumerationFailureCount: Int = 0,
        addressFailureCount: Int = 0,
        ldcmStatus: String = ""
    ) {
        self.overcurrentCount = overcurrentCount
        self.linkErrorCount = linkErrorCount
        self.enumerationFailureCount = enumerationFailureCount
        self.addressFailureCount = addressFailureCount
        self.ldcmStatus = ldcmStatus
    }
}
