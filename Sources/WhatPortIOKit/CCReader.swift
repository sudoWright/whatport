import Foundation
import IOKit

// Reads CC (communication channel) connection state from all port types.
//
// Each port (USB-C, MagSafe, etc.) has an IOPortTransportStateCC service.
// Its "Active" property indicates whether anything is physically connected.
//
// ParentBuiltInPortNumber maps each CC service to its physical port, but
// different port types can share the same number (e.g. MagSafe and USB-C
// port 1 both report ParentBuiltInPortNumber = 1). We use
// ParentPortTypeDescription to distinguish them.

public struct RawCCData: Sendable {
    public let portNumber: Int
    public let portType: String   // "USB-C", "MagSafe 3", etc.
    public let active: Bool
}

public enum CCReader {
    public static func readAll() -> [RawCCData] {
        var results: [RawCCData] = []
        // Dedup key: (portNumber, portType) since different types share numbers
        var seen = Set<String>()

        withMatchingServices(className: "IOPortTransportStateCC") { service in
            guard let props = ioProperties(service) else { return }

            let portNumber = ioInt(props["ParentBuiltInPortNumber"])
            let portType = ioString(props["ParentPortTypeDescription"])
            let active = ioBool(props["Active"])

            let key = "\(portNumber):\(portType)"
            guard portNumber > 0, !seen.contains(key) else { return }
            seen.insert(key)

            results.append(RawCCData(portNumber: portNumber, portType: portType, active: active))
        }

        return results.sorted { $0.portNumber < $1.portNumber }
    }
}
