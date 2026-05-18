import Foundation
import IOKit

// Reads connected USB device info from IOUSBHostDevice services.
//
// Each USB device's parent is a USB port (AppleUSB30XHCIARMPort or
// AppleUSB20XHCIARMPort) which has "UsbCPortNumber" mapping directly
// to the physical USB-C port. One level up, no tree walking needed.
//
// Device Speed values (from IOUSBHostFamily):
//   0 = Low Speed (1.5 Mbps)
//   1 = Full Speed (12 Mbps)
//   2 = High Speed (480 Mbps, USB 2.0)
//   3 = Super Speed (5 Gbps, USB 3.0)
//   4 = Super Speed Plus (10 Gbps, USB 3.2 Gen 2)
//   5 = Super Speed Plus (20 Gbps, USB 3.2 Gen 2x2)

public struct RawDeviceInfo: Sendable {
    public let portNumber: Int       // physical USB-C port
    public let productName: String
    public let vendorName: String
    public let speedCode: Int        // Device Speed enum value
    public let usbVersion: Int       // bcdUSB (e.g. 800 = USB 3.2)
    public let deviceClass: Int      // bInterfaceClass (8 = storage, etc.)
    public let currentDraw: Int      // UsbPowerSinkAllocation in mA
    public let serialNumber: String  // kUSBSerialNumberString (hex-encoded)
}

public enum DeviceReader {
    public static func readUSBDevices() -> [RawDeviceInfo] {
        var results: [RawDeviceInfo] = []
        var seen = Set<Int>()

        withMatchingServices(className: "IOUSBHostDevice") { service in
            guard let props = ioProperties(service) else { return }

            let productName = ioString(props["USB Product Name"])
            guard !productName.isEmpty else { return }

            // Dedup by locationID (same device appears at multiple levels)
            let locationID = ioInt(props["locationID"])
            guard locationID > 0, !seen.contains(locationID) else { return }
            seen.insert(locationID)

            // UsbCPortNumber on the parent USB port gives the physical
            // port directly. Falls back to walking 3 levels up to the
            // usb-drd node's port-number if UsbCPortNumber is absent.
            let portNumber = ioInt(ioParentProperty(service, key: "UsbCPortNumber"))
                .nonZero ?? ioDataInt(ioAncestorProperty(service, key: "port-number", levels: 3)) ?? 0

            results.append(RawDeviceInfo(
                portNumber: portNumber,
                productName: productName,
                vendorName: ioString(props["USB Vendor Name"]),
                speedCode: ioInt(props["Device Speed"]),
                usbVersion: ioInt(props["bcdUSB"]),
                deviceClass: ioInt(props["bDeviceClass"]),
                currentDraw: ioInt(props["UsbPowerSinkAllocation"]),
                serialNumber: ioString(props["kUSBSerialNumberString"])
            ))
        }

        return results
    }
}

// Small helper to treat 0 as nil for optional chaining.
private extension Int {
    var nonZero: Int? { self != 0 ? self : nil }
}
