import Foundation
import IOKit

// Read-only AppleSMC access. The 80-byte wire layout and key commands are
// cross-checked against the MIT-licensed fanpro SMC reference:
// https://github.com/omar16100/fanpro/blob/main/docs/smc_reference.md
struct SystemFanSensor: FanSensing {
    func currentState() async -> FanReadoutState {
        await Task.detached(priority: .utility) {
            SMCFanReader.readState()
        }.value
    }
}

enum SMCNumericDecoder {
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        let value: Double?
        switch type {
        case "flt " where bytes.count == 4:
            let bits = littleEndianUInt32(bytes)
            value = Double(Float(bitPattern: bits))
        case "ui8 " where bytes.count == 1, "flag" where bytes.count == 1:
            value = Double(bytes[0])
        case "ui16" where bytes.count == 2, "ui32" where bytes.count == 4:
            value = Double(bigEndianUInt32(bytes))
        case "si8 " where bytes.count == 1:
            value = Double(Int8(bitPattern: bytes[0]))
        case "si16" where bytes.count == 2:
            value = Double(Int16(bitPattern: UInt16(bigEndianUInt32(bytes))))
        default:
            value = decodeFixedPoint(type: type, bytes: bytes)
        }
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func decodeFixedPoint(type: String, bytes: [UInt8]) -> Double? {
        let characters = Array(type)
        guard characters.count == 4, characters[1] == "p", bytes.count == 2,
              let wholeBits = characters[2].hexDigitValue,
              let fractionBits = characters[3].hexDigitValue else { return nil }
        let raw = UInt16(bigEndianUInt32(bytes))
        if characters[0] == "f", wholeBits + fractionBits == 16 {
            return Double(raw) / Double(1 << fractionBits)
        }
        if characters[0] == "s", wholeBits + fractionBits == 15 {
            return Double(Int16(bitPattern: raw)) / Double(1 << fractionBits)
        }
        return nil
    }

    private static func littleEndianUInt32(_ bytes: [UInt8]) -> UInt32 {
        bytes.enumerated().reduce(0) { value, pair in
            value | (UInt32(pair.element) << (pair.offset * 8))
        }
    }

    private static func bigEndianUInt32(_ bytes: [UInt8]) -> UInt32 {
        bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

private enum SMCFanReader {
    static func readState() -> FanReadoutState {
        guard let connection = SMCReadConnection() else { return .unavailable }
        defer { connection.close() }

        guard let rawCount = connection.number(for: "FNum"),
              rawCount.isFinite, rawCount >= 0, rawCount <= 8,
              rawCount.rounded(.towardZero) == rawCount else { return .unavailable }
        let count = Int(rawCount)
        if count == 0 {
            return FanReadoutState(availability: .fanless, fans: [], observedAt: Date())
        }

        let modeSuffix = connection.number(for: "F0Md") != nil ? "Md"
            : (connection.number(for: "F0md") != nil ? "md" : nil)

        let fans = (0..<count).map { index in
            let prefix = "F\(index)"
            let modeValue = modeSuffix.flatMap { connection.number(for: prefix + $0) }
            let mode: FanControlMode = switch modeValue {
            case 0: .automatic
            case 1: .manual
            case 3: .system
            default: .unknown
            }
            return FanReading(
                index: index,
                currentRPM: nonnegative(connection.number(for: prefix + "Ac")),
                minimumRPM: nonnegative(connection.number(for: prefix + "Mn")),
                maximumRPM: nonnegative(connection.number(for: prefix + "Mx")),
                targetRPM: nonnegative(connection.number(for: prefix + "Tg")),
                mode: mode
            )
        }
        return FanReadoutState(availability: .available, fans: fans, observedAt: Date())
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

private final class SMCReadConnection {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            return nil
        }
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    func number(for name: String) -> Double? {
        guard let key = Self.fourCC(name),
              let info = call(key: key, command: 9),
              let size = Self.nativeUInt32(info, at: 28),
              let typeValue = Self.nativeUInt32(info, at: 32),
              (1...4).contains(size),
              let response = call(key: key, command: 5, dataSize: size) else { return nil }
        let type = Self.fourCCString(typeValue)
        return SMCNumericDecoder.decode(
            type: type,
            bytes: Array(response[48..<(48 + Int(size))])
        )
    }

    private func call(key: UInt32, command: UInt8, dataSize: UInt32 = 0) -> [UInt8]? {
        var input = [UInt8](repeating: 0, count: 80)
        var output = [UInt8](repeating: 0, count: 80)
        var outputSize = output.count
        Self.putNativeUInt32(key, in: &input, at: 0)
        Self.putNativeUInt32(dataSize, in: &input, at: 28)
        input[42] = command // Only READ_KEYINFO (9) and READ_BYTES (5).

        let result = input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                IOConnectCallStructMethod(
                    connection, 2, inputBuffer.baseAddress, inputBuffer.count,
                    outputBuffer.baseAddress, &outputSize
                )
            }
        }
        guard result == KERN_SUCCESS, outputSize == 80, output[40] == 0 else {
            return nil
        }
        return output
    }

    private static func putNativeUInt32(_ value: UInt32, in bytes: inout [UInt8], at offset: Int) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
        }
    }

    private static func nativeUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard bytes.count >= offset + 4 else { return nil }
        return (0..<4).reduce(0) { value, index in
            value | (UInt32(bytes[offset + index]) << (index * 8))
        }
    }

    private static func fourCC(_ name: String) -> UInt32? {
        let bytes = Array(name.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCCString(_ value: UInt32) -> String {
        String(bytes: (0..<4).map { index in
            UInt8(truncatingIfNeeded: value >> ((3 - index) * 8))
        }, encoding: .ascii) ?? "????"
    }
}
