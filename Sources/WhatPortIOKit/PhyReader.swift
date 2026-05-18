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
    // Physical port number from the parent atc-phy device tree node.
    // 0 means the property wasn't found (older macOS or different hardware).
    public let portNumber: Int
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

            // Read port-number from the parent atc-phy device tree node.
            // This is the direct hardware mapping from PHY controller to
            // physical USB-C port. It's more reliable than positional mapping
            // because some Macs have more PHY controllers than physical ports
            // (e.g. M4 Pro has 4 PHYs for 3 ports).
            let portNumber = ioDataInt(ioParentProperty(service, key: "port-number")) ?? 0

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
                portNumber: portNumber,
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
