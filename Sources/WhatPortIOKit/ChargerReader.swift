import Foundation
import IOKit

// Reads the negotiated USB-PD power contract from IOPortFeaturePowerSource.
//
// Each port that receives power (MagSafe, USB-C acting as sink) has an
// IOPortFeaturePowerSource child with a "WinningPowerSourceOption" dict
// showing the selected PDO: max watts, voltage, and current.
//
// MagSafe ports don't have WinningPowerSourceOption. They do have
// PowerSourceOptions (an array of available PDOs). We fall back to
// the highest-power PDO in that array.
//
// We use this for MagSafe because PowerOutDetails only tracks power
// the laptop delivers OUT. MagSafe power comes IN, so it needs a
// different data source.

public struct RawChargerData: Sendable {
    public let portType: String   // "MagSafe 3", "USB-C", etc.
    public let portNumber: Int
    public let maxWatts: Int      // milliwatts
    public let voltage: Int       // millivolts
    public let maxCurrent: Int    // milliamps
}

public enum ChargerReader {
    public static func readAll() -> [RawChargerData] {
        var results: [RawChargerData] = []

        withMatchingServices(className: "IOPortFeaturePowerSource") { service in
            guard let props = ioProperties(service) else { return }

            // Only read USB-PD sources (skip Brick ID, TypeC fallback, etc.)
            let name = ioString(props["PowerSourceName"])
            guard name == "USB-PD" else { return }

            let portType = ioString(props["ParentPortTypeDescription"])
            let portNumber = ioInt(props["ParentBuiltInPortNumber"])

            // Try WinningPowerSourceOption first (the PDO the system selected).
            // USB-C ports have this, MagSafe does not.
            var pdo = ioDictionary(props["WinningPowerSourceOption"])

            // Fallback: pick the highest-power PDO from PowerSourceOptions.
            // MagSafe exposes the array of available PDOs but not which one
            // was selected, so we take the max-wattage entry as the best
            // approximation of the negotiated contract.
            if pdo.isEmpty {
                pdo = highestPDO(from: ioArray(props["PowerSourceOptions"]))
            }

            guard !pdo.isEmpty else { return }

            let maxWatts = ioInt(pdo["Max Power (mW)"])
            let voltage = ioInt(pdo["Voltage (mV)"])
            let maxCurrent = ioInt(pdo["Max Current (mA)"])

            guard maxWatts > 0 else { return }

            results.append(RawChargerData(
                portType: portType,
                portNumber: portNumber,
                maxWatts: maxWatts,
                voltage: voltage,
                maxCurrent: maxCurrent
            ))
        }

        return results
    }

    // Finds the PDO with the highest Max Power from an array of option dicts.
    private static func highestPDO(from options: [Any]) -> [String: Any] {
        var best: [String: Any] = [:]
        var bestWatts = 0
        for option in options {
            let dict = ioDictionary(option)
            let watts = ioInt(dict["Max Power (mW)"])
            if watts > bestWatts {
                bestWatts = watts
                best = dict
            }
        }
        return best
    }
}
