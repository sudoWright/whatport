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
}
