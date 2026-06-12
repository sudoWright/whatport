import Foundation
import IOKit

// Reads the physical USB-C / MagSafe port roster from the HPM port-controller
// layer. This is the authoritative list of physical ports: each entry carries
// a stable UUID (read from the HPM controller ancestor) that uniquely
// identifies the port, even when MagSafe and USB-C share the same "@N" number.
//
// Port-interface classes vary by chip generation:
//   AppleHPMInterfaceType10/11/12/18  - M3+ (USB-C / MagSafe / variants)
//   AppleTCControllerType10/11        - M1 / M2 (USB-C / MagSafe)
//
// Each real port node is named "Port-USB-C@N" / "Port-MagSafe 3@N" and has a
// "PortTypeDescription" property. There can be more interface instances than
// physical ports (e.g. internal DRD nodes), so we filter to real connectors.
//
// The UUID is an in-session join key only. It is never shown in the UI.

public struct RawHPMPort: Sendable {
    public let uuid: String      // HPM controller UUID (raw, with dashes)
    public let portNumber: Int   // the "@N" suffix
    public let portType: String  // "USB-C", "MagSafe 3", etc.
    public let serviceName: String
    public let overcurrentCount: Int
    public let plugEventCount: Int
    public let connectionCount: Int
    public let authorizationStatus: String
    public let ldcmStatus: String

    public var isMagSafe: Bool {
        portType.lowercased().contains("magsafe")
    }
}

public enum HPMReader {
    // Candidate port-interface classes across chip generations. We enumerate
    // all of them; only the ones present on this Mac return services.
    private static let interfaceClasses = [
        "AppleHPMInterfaceType10",
        "AppleHPMInterfaceType11",
        "AppleHPMInterfaceType12",
        "AppleHPMInterfaceType18",
        "AppleTCControllerType10",
        "AppleTCControllerType11",
    ]

    public static func readAll() -> [RawHPMPort] {
        var results: [RawHPMPort] = []
        var seen = Set<String>()  // dedup by "portType:portNumber"

        for className in interfaceClasses {
            withMatchingServices(className: className) { service in
                guard let name = ioEntryName(service), name.hasPrefix("Port-") else { return }

                // Real physical ports report a USB-C or MagSafe port type.
                let portType = ioString(ioProperty(service, key: "PortTypeDescription"))
                let isRealPort = portType == "USB-C" || portType.hasPrefix("MagSafe")
                guard isRealPort else { return }

                // The "@N" number is the location in the service plane, not
                // part of the registry name (the name is just "Port-USB-C").
                guard let portNumber = ioLocationInPlaneInt(service) else { return }

                // The UUID lives on the HPM controller ancestor, not here.
                guard let uuid = ioHPMControllerUUID(service), !uuid.isEmpty else { return }

                let key = "\(portType):\(portNumber)"
                guard !seen.contains(key) else { return }
                seen.insert(key)

                let overcurrentCount = ioInt(ioProperty(service, key: "Overcurrent Count"))
                let plugEventCount = ioInt(ioProperty(service, key: "Plug Event Count"))
                let connectionCount = ioInt(ioProperty(service, key: "ConnectionCount"))
                let authorizationStatus = ioString(ioProperty(service, key: "UserAuthorizationStatusDescription"))
                let ldcmStatus = ioString(ioProperty(service, key: "LDCM_MeasurementStatusDescription"))

                results.append(RawHPMPort(
                    uuid: uuid,
                    portNumber: portNumber,
                    portType: portType,
                    serviceName: name,
                    overcurrentCount: overcurrentCount,
                    plugEventCount: plugEventCount,
                    connectionCount: connectionCount,
                    authorizationStatus: authorizationStatus,
                    ldcmStatus: ldcmStatus
                ))
            }
        }

        return results.sorted { $0.portNumber < $1.portNumber }
    }
}
