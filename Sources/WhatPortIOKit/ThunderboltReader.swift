import Foundation
import IOKit

// Reads per-port Thunderbolt/USB4 link state from IOThunderboltPort services.
//
// Each USB-C port has several logical adapters (TB port, DP adapter, PCIe adapter,
// USB adapter, NHI adapter). We filter to adapters where Description = "Thunderbolt Port"
// because those are the ones with Socket ID mapping to physical ports.
//
// Socket ID is a string ("1", "2", "4") that maps directly to the physical
// USB-C port number.

public struct RawThunderboltData: Sendable {
    public let socketID: String
    public let portNumber: Int
    public let currentLinkWidth: Int
    public let currentLinkSpeed: Int
    public let supportedLinkWidth: Int
    public let supportedLinkSpeed: Int
    public let targetLinkWidth: Int
    public let targetLinkSpeed: Int
    public let linkBandwidth: Int
    public let description: String
    public let thunderboltVersion: Int
    public let dualLinkPort: Int

    // Speed reference (from research):
    //   0 = idle
    //   4 = 20 Gbps/lane (USB4 Gen3 / TB4)
    //  12 = 40 Gbps/lane (USB4 Gen4 / TB5)
    public var isActive: Bool {
        currentLinkWidth > 0 && currentLinkSpeed > 0
    }
}

public enum ThunderboltReader {
    public static func readAll() -> [RawThunderboltData] {
        var results: [RawThunderboltData] = []

        withMatchingServices(className: "IOThunderboltPort") { service in
            guard let props = ioProperties(service) else { return }

            let desc = ioString(props["Description"])

            // Only keep "Thunderbolt Port" adapters. These have Socket ID
            // and represent physical USB-C ports.
            guard desc == "Thunderbolt Port" else { return }

            let data = RawThunderboltData(
                socketID: ioString(props["Socket ID"]),
                portNumber: ioInt(props["Port Number"]),
                currentLinkWidth: ioInt(props["Current Link Width"]),
                currentLinkSpeed: ioInt(props["Current Link Speed"]),
                supportedLinkWidth: ioInt(props["Supported Link Width"]),
                supportedLinkSpeed: ioInt(props["Supported Link Speed"]),
                targetLinkWidth: ioInt(props["Target Link Width"]),
                targetLinkSpeed: ioInt(props["Target Link Speed"]),
                linkBandwidth: ioInt(props["Link Bandwidth"]),
                description: desc,
                thunderboltVersion: ioInt(props["Thunderbolt Version"]),
                dualLinkPort: ioInt(props["Dual-Link Port"])
            )
            results.append(data)
        }

        return results
    }
}
