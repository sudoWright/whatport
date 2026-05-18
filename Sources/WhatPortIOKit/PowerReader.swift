import Foundation
import IOKit

// Reads per-port power delivery data from AppleSmartBattery.PowerOutDetails.
//
// PowerOutDetails is an array of dictionaries, one per port that is currently
// sourcing power. If no ports are sourcing power, the array may be empty or
// the key may be absent entirely.
//
// Power values use centiwatts (divide by 100 for watts), milliamps, and millivolts.
// This reader returns raw values; conversion happens in the domain layer.
//
// Important: PowerOutDetails does NOT fire IOKit notifications when it updates.
// It must be polled (every 2-5 seconds). This is handled in Chunk 4.

public struct RawPowerData: Sendable {
    public let portIndex: Int
    public let watts: Int
    public let current: Int
    public let adapterVoltage: Int
    public let configuredVoltage: Int
    public let configuredCurrent: Int
    public let pdPowerMW: Int
    public let filteredPower: Int
    public let vconnCurrent: Int
    public let vconnPower: Int
    public let vconnMaxCurrent: Int
    public let powerState: Int
}

public enum PowerReader {
    public static func readAll() -> [RawPowerData] {
        var results: [RawPowerData] = []

        // AppleSmartBattery is a single service instance.
        withMatchingServices(className: "AppleSmartBattery") { service in
            // PowerOutDetails is an array property on the battery service.
            guard let raw = ioProperty(service, key: "PowerOutDetails") else { return }
            let entries = ioArray(raw)

            for entry in entries {
                let dict = ioDictionary(entry)
                let data = RawPowerData(
                    portIndex: ioInt(dict["PortIndex"]),
                    watts: ioInt(dict["Watts"]),
                    current: ioInt(dict["Current"]),
                    adapterVoltage: ioInt(dict["AdapterVoltage"]),
                    configuredVoltage: ioInt(dict["ConfiguredVoltage"]),
                    configuredCurrent: ioInt(dict["ConfiguredCurrent"]),
                    pdPowerMW: ioInt(dict["PDPowermW"]),
                    filteredPower: ioInt(dict["FilteredPower"]),
                    vconnCurrent: ioInt(dict["VConnCurrent"]),
                    vconnPower: ioInt(dict["VConnPower"]),
                    vconnMaxCurrent: ioInt(dict["VConnMaxCurrent"]),
                    powerState: ioInt(dict["PowerState"])
                )
                results.append(data)
            }
        }

        return results
    }

    // Check whether PowerOutDetails is available on this machine.
    // Desktop Macs and some older laptops don't have it.
    public static func isPowerMeteringAvailable() -> Bool {
        var available = false
        withMatchingServices(className: "AppleSmartBattery") { service in
            if ioProperty(service, key: "PowerOutDetails") != nil {
                available = true
            }
        }
        return available
    }
}
