import Foundation
import IOKit

// Reads per-port power-OUT from the System Management Controller (SMC).
//
// On desktops (Mac mini / Studio / Pro) there is no battery controller, so the
// AppleSmartBattery power paths the laptop pipeline uses are empty. The per-port
// power-OUT figures still exist; they live in the SMC on channels D1..D4. Each
// channel carries a `DxUI` key whose value equals the port controller's HPM
// `UUID`, which is how a channel is tied to a physical port. The SMC D-index is
// NOT the physical port number (verified on M5: D3 = USB-C@4, D4 = MagSafe@1),
// so the UUID is the only correct join.
//
// This opens an AppleSMC user client (the long-standing public ABI used by
// powermetrics / smcFanControl), unlike every other reader which reads IOKit
// registry properties. All reads are read-only. If the open ever fails, every
// method degrades to "no data" rather than crashing.

public struct RawSMCPortPower: Sendable {
    public let channel: Int       // SMC D-index (1..4), NOT the physical port
    public let present: Bool      // DxPR: something is drawing on this channel
    public let volts: Double      // DxJV
    public let amps: Double       // DxJI
    public let uuid: String       // DxUI, 32-char lowercase hex (join key)

    public var watts: Double { volts * amps }
}

public final class SMCPowerReader {
    private var connection: io_connect_t = 0

    public init() {
        // The kernel reads this struct at fixed C offsets and rejects any other
        // size. Catch a layout regression in debug builds.
        assert(
            MemoryLayout<SMCParamStruct>.stride == 80,
            "SMCParamStruct must be 80 bytes, got \(MemoryLayout<SMCParamStruct>.stride)"
        )
    }

    deinit { close() }

    // Opens the AppleSMC user client. Idempotent. Returns false when AppleSMC
    // is missing or the open is refused.
    @discardableResult
    public func open() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return false }
        connection = conn
        return true
    }

    public func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // Reads channels D1..D4. A channel is only returned when it has a usable
    // DxUI, since without it the channel can't be tied to a port.
    public func readPortPowerChannels() -> [RawSMCPortPower] {
        guard open() else { return [] }
        var channels: [RawSMCPortPower] = []
        for index in 1...4 {
            guard let uuid = readUUID("D\(index)UI"), !uuid.isEmpty else { continue }
            channels.append(RawSMCPortPower(
                channel: index,
                present: (readUInt8("D\(index)PR") ?? 0) >= 1,
                volts: Double(readFloat("D\(index)JV") ?? 0),
                amps: Double(readFloat("D\(index)JI") ?? 0),
                uuid: uuid
            ))
        }
        return channels
    }

    // MARK: - Key reads

    private func readFloat(_ key: String) -> Float? {
        guard let bytes = readKey(key) else { return nil }
        return Self.decodeFloat(bytes)
    }

    // Decode an SMC `flt` payload (4-byte IEEE float, little-endian on Apple
    // Silicon). Returns nil for short payloads and non-finite values: an
    // uninitialised channel can carry an inf/NaN bit pattern, and letting it
    // through would trap downstream unit conversions. Internal for testing.
    static func decodeFloat(_ bytes: [UInt8]) -> Float? {
        guard bytes.count >= 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Float(bitPattern: bits)
        return value.isFinite ? value : nil
    }

    private func readUInt8(_ key: String) -> UInt8? {
        guard let bytes = readKey(key), let first = bytes.first else { return nil }
        return first
    }

    // `hex_` keys (DxUI): 16 raw bytes as 32 lowercase hex chars, matching the
    // dash-stripped lowercase HPM UUID. A channel with no controller reads
    // all-zero; treat that as absent. Internal for testing.
    func readUUID(_ key: String) -> String? {
        guard let bytes = readKey(key), !bytes.isEmpty else { return nil }
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        return Self.hexString(bytes)
    }

    static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - SMC ABI

    // Reads one SMC key's raw bytes: ask for its size/type, then read the value.
    private func readKey(_ key: String) -> [UInt8]? {
        guard let fourCC = Self.fourCC(key) else { return nil }

        var info = SMCParamStruct()
        info.key = fourCC
        info.data8 = Self.cmdGetKeyInfo
        guard let infoOut = callDriver(&info) else { return nil }
        let size = infoOut.keyInfo.dataSize
        guard size > 0 else { return nil }

        var read = SMCParamStruct()
        read.key = fourCC
        read.keyInfo.dataSize = size
        read.keyInfo.dataType = infoOut.keyInfo.dataType
        read.data8 = Self.cmdReadKey
        guard let readOut = callDriver(&read) else { return nil }

        let count = Int(min(size, 32))
        var value = readOut.bytes
        return withUnsafeBytes(of: &value) { Array($0.prefix(count)) }
    }

    private func callDriver(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            Self.kernelIndex,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return kr == KERN_SUCCESS ? output : nil
    }

    // Packs a 4-character key into its FourCC UInt32 (MSB first).
    static func fourCC(_ key: String) -> UInt32? {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count == 4 else { return nil }
        var value: UInt32 = 0
        for scalar in scalars {
            guard scalar.value <= 0xFF else { return nil }
            value = (value << 8) | UInt32(scalar.value)
        }
        return value
    }

    private static let kernelIndex: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9
}

// MARK: - AppleSMC user-client ABI structs
//
// Mirror the C layout used by powermetrics / smcFanControl byte-for-byte. Field
// order and types must not change: the kernel reads this struct at fixed
// offsets. MemoryLayout<SMCParamStruct>.stride must be 80 bytes.

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    // C keeps keyInfo's 3-byte trailing padding before `result`; Swift would
    // otherwise pack `result` into it and shrink the struct to 76 bytes, which
    // the kernel rejects. This explicit pad restores the C offsets (total 80).
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
