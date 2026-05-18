import Foundation
import IOKit

// Reads USB-C CC (communication channel) connection state.
//
// Each USB-C port has an IOPortTransportStateCC service. Its "Active"
// property indicates whether anything is physically connected to the
// port, even if there's no data transport (e.g. a power-only charger).
//
// We use ParentBuiltInPortNumber to map each CC service to its
// physical port number.

public struct RawCCData: Sendable {
    public let portNumber: Int
    public let active: Bool
}

public enum CCReader {
    public static func readAll() -> [RawCCData] {
        var results: [RawCCData] = []
        var seen = Set<Int>()

        withMatchingServices(className: "IOPortTransportStateCC") { service in
            guard let props = ioProperties(service) else { return }

            let portNumber = ioInt(props["ParentBuiltInPortNumber"])
            let active = ioBool(props["Active"])

            // Deduplicate by port number (some ports have multiple CC entries)
            guard portNumber > 0, !seen.contains(portNumber) else { return }
            seen.insert(portNumber)

            results.append(RawCCData(portNumber: portNumber, active: active))
        }

        return results.sorted { $0.portNumber < $1.portNumber }
    }
}
