import Foundation
import IOKit

// Reads per-port PHY lane allocation from AppleTypeCPhy services.
//
// Each USB-C port has one PHY instance with two lanes (Lane 0 and Lane 1)
// plus a USB2 channel. Each lane can be idle, carrying Thunderbolt/USB4
// traffic ("CIO"), or carrying DisplayPort alt-mode.
//
// We match the superclass "AppleTypeCPhy" rather than the chip-specific
// "AppleT8132TypeCPhy" so this works across M-series generations.

public struct RawPhyData: Sendable {
    public let phyID: Int
    public let lane0Transport: String
    public let lane0PowerLevel: String
    public let lane0Client: String
    public let lane1Transport: String
    public let lane1PowerLevel: String
    public let lane1Client: String
    public let usb2Transport: String
    public let usb2Client: String
    public let dpLinkRate: String
    public let dpTunnel: String

    public var hasActiveTransport: Bool {
        !lane0Transport.isEmpty || !lane1Transport.isEmpty
    }
}

public enum PhyReader {
    public static func readAll() -> [RawPhyData] {
        var results: [RawPhyData] = []

        withMatchingServices(className: "AppleTypeCPhy") { service in
            guard let props = ioProperties(service) else { return }

            let phyID = ioInt(props["AppleTypeCPhyID"])

            // Lane data is nested: "AppleTypeCPhyLane" -> "Lane 0" -> "Transport"
            let lanes = ioDictionary(props["AppleTypeCPhyLane"])
            let lane0 = ioDictionary(lanes["Lane 0"])
            let lane1 = ioDictionary(lanes["Lane 1"])

            // USB2 is a separate sub-dictionary
            let usb2 = ioDictionary(props["AppleTypeCPhyUSB2"])

            // DisplayPort pixel clock info (present when DP is active)
            let dpPclk = ioDictionary(props["AppleTypeCPhyDisplayPortPclk"])
            let dpTunnel = ioString(props["AppleTypeCPhyDisplayPortTunnel"])

            let data = RawPhyData(
                phyID: phyID,
                lane0Transport: ioString(lane0["Transport"]),
                lane0PowerLevel: ioString(lane0["Power Level"]),
                lane0Client: ioString(lane0["Client"]),
                lane1Transport: ioString(lane1["Transport"]),
                lane1PowerLevel: ioString(lane1["Power Level"]),
                lane1Client: ioString(lane1["Client"]),
                usb2Transport: ioString(usb2["Transport"]),
                usb2Client: ioString(usb2["Client"]),
                dpLinkRate: ioString(dpPclk["Link Rate"]),
                dpTunnel: dpTunnel
            )
            results.append(data)
        }

        return results.sorted { $0.phyID < $1.phyID }
    }
}
