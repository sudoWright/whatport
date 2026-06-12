import Foundation
import IOKit

// Reads USB port lifetime statistics from XHCI port services.
//
// Each USB-C port has a SuperSpeed port service (AppleUSB30XHCIARMPort
// or similar) with a "port-statistics" dictionary containing lifetime
// counters: how many times a device was connected, error counts, and
// time spent in each power state.
//
// We match on the "UsbCPortNumber" property to map each XHCI port
// to its physical USB-C port.

public struct RawPortStats: Sendable {
    public let portNumber: Int
    public let connectCount: Int
    public let overcurrentCount: Int
    public let enumerationFailureCount: Int
    public let addressFailureCount: Int
    public let linkErrorCount: Int
    public let remoteWakeCount: Int
}

public enum PortStatsReader {
    public static func readAll() -> [RawPortStats] {
        var results: [RawPortStats] = []
        var seen = Set<Int>()

        // SuperSpeed ports have the detailed stats.
        // The class name varies by chip, so match on the property instead.
        withMatchingServices(className: "IOUSBHostDevice") { service in
            // Use the device-tree "port-number" (the true physical port,
            // matching the HPM @N) rather than the XHCI "UsbCPortNumber",
            // which numbers ports sequentially and disagrees on Macs that
            // skip a port. Keeps stats aligned with the rest of the roster.
            let portNumber = ioFirstAncestorDataInt(service, key: "port-number", maxLevels: 10)
                ?? ioInt(ioParentProperty(service, key: "UsbCPortNumber"))
            guard portNumber > 0, !seen.contains(portNumber) else { return }
            seen.insert(portNumber)

            // port-statistics is on the parent port, not the device
            guard let statsRaw = ioParentProperty(service, key: "port-statistics"),
                  let stats = statsRaw as? [String: Any] else { return }

            results.append(RawPortStats(
                portNumber: portNumber,
                connectCount: ioInt(stats["kPortStatConnectCount"]),
                overcurrentCount: ioInt(stats["kPortStatOverCurrentCount"]),
                enumerationFailureCount: ioInt(stats["kPortStatEnumerationFailureCount"]),
                addressFailureCount: ioInt(stats["kPortStatAddressFailureCount"]),
                linkErrorCount: ioInt(stats["kPortStatEOF2ViolationCount"]),
                remoteWakeCount: ioInt(stats["kPortStatRemoteWakeCount"])
            ))
        }

        return results
    }
}
