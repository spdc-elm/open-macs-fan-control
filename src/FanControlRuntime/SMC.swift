import Foundation
import IOKit
import CSMCBridge

enum SMCError: LocalizedError {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case invalidKey(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service was not found"
        case .openFailed(let code):
            return "failed to open AppleSMC connection (kern_return_t=\(code))"
        case .callFailed(let code):
            return "AppleSMC call failed (kern_return_t=\(code))"
        case .invalidKey(let key):
            return "invalid SMC key: \(key)"
        case .invalidData(let message):
            return message
        }
    }
}

package struct FanReading {
    package let index: Int
    package let currentRPM: Int
    package let minimumRPM: Int
    package let maximumRPM: Int
    package let targetRPM: Int?
    package let modeValue: Int?

    package var modeDescription: String {
        guard let modeValue else { return "unknown" }
        return modeValue == 0 ? "auto" : "manual(\(modeValue))"
    }
}

package final class SMCConnection {
    private let connection: io_connect_t

    private init(connection: io_connect_t) {
        self.connection = connection
    }

    package static func open() throws -> SMCConnection {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCError.serviceNotFound
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            throw SMCError.serviceNotFound
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            throw SMCError.openFailed(result)
        }

        return SMCConnection(connection: connection)
    }

    package func close() {
        IOServiceClose(connection)
    }

    package func readFans() throws -> [FanReading] {
        let fanCount = try readUnsignedInt(key: "FNum")
        return try (0..<fanCount).map { try readFan(index: $0) }
    }

    package func readFan(index: Int) throws -> FanReading {
        FanReading(
            index: index,
            currentRPM: Int(round(try readRPM(key: fanKey(index, suffix: "Ac")))),
            minimumRPM: Int(round((try? readRPM(key: fanKey(index, suffix: "Mn"))) ?? 0)),
            maximumRPM: Int(round((try? readRPM(key: fanKey(index, suffix: "Mx"))) ?? 0)),
            targetRPM: try? Int(round(readRPM(key: fanKey(index, suffix: "Tg")))),
            modeValue: try? readUnsignedInt(key: fanKey(index, suffix: "Md"))
        )
    }

    func readTemperature(key: String) throws -> Double {
        let result = try read(key: key)
        switch result.dataType {
        case "sp78":
            guard result.bytes.count >= 2 else {
                throw SMCError.invalidData("\(key) returned too few bytes for sp78")
            }
            let signed = Int16(bitPattern: UInt16(result.bytes[0]) << 8 | UInt16(result.bytes[1]))
            return Double(signed) / 256.0
        case "flt ":
            guard result.bytes.count >= 4 else {
                throw SMCError.invalidData("\(key) returned too few bytes for flt")
            }
            return Double(nativeFloat(from: result.bytes))
        case "fp88":
            guard result.bytes.count >= 2 else {
                throw SMCError.invalidData("\(key) returned too few bytes for fp88")
            }
            let raw = UInt16(result.bytes[0]) << 8 | UInt16(result.bytes[1])
            return Double(raw) / 256.0
        default:
            throw SMCError.invalidData("unsupported temperature type for \(key): \(result.dataType)")
        }
    }

    func readRPM(key: String) throws -> Double {
        let result = try read(key: key)
        switch result.dataType {
        case "fpe2":
            guard result.bytes.count >= 2 else {
                throw SMCError.invalidData("\(key) returned too few bytes for fpe2")
            }
            let raw = UInt16(result.bytes[0]) << 8 | UInt16(result.bytes[1])
            return Double(raw) / 4.0
        case "flt ":
            guard result.bytes.count >= 4 else {
                throw SMCError.invalidData("\(key) returned too few bytes for flt")
            }
            return Double(nativeFloat(from: result.bytes))
        default:
            throw SMCError.invalidData("unsupported RPM type for \(key): \(result.dataType)")
        }
    }

    func readUnsignedInt(key: String) throws -> Int {
        let result = try read(key: key)
        switch result.dataType {
        case "ui8 ", "ui8":
            guard let value = result.bytes.first else {
                throw SMCError.invalidData("\(key) returned no bytes")
            }
            return Int(value)
        case "ui16":
            guard result.bytes.count >= 2 else {
                throw SMCError.invalidData("\(key) returned too few bytes for ui16")
            }
            return Int(UInt16(result.bytes[0]) << 8 | UInt16(result.bytes[1]))
        case "ui32":
            guard result.bytes.count >= 4 else {
                throw SMCError.invalidData("\(key) returned too few bytes for ui32")
            }
            return Int(UInt32(result.bytes[0]) << 24 | UInt32(result.bytes[1]) << 16 | UInt32(result.bytes[2]) << 8 | UInt32(result.bytes[3]))
        default:
            throw SMCError.invalidData("unsupported integer type for \(key): \(result.dataType)")
        }
    }

    package func setFanManualMode(index: Int) throws {
        let modeKey = fanKey(index, suffix: "Md")
        if (try? write(key: modeKey, dataType: "ui8", bytes: [1])) != nil {
            return
        }

        let maskKey = "FS! "
        let currentMask = (try? readUnsignedInt(key: maskKey)) ?? 0
        let updatedMask = currentMask | (1 << index)
        try writeUnsignedInt(key: maskKey, value: updatedMask)
    }

    package func restoreAutomaticMode(index: Int) throws {
        let modeKey = fanKey(index, suffix: "Md")
        if (try? write(key: modeKey, dataType: "ui8", bytes: [0])) != nil {
            return
        }

        let maskKey = "FS! "
        let currentMask = (try? readUnsignedInt(key: maskKey)) ?? 0
        let updatedMask = currentMask & ~(1 << index)
        try writeUnsignedInt(key: maskKey, value: updatedMask)
    }

    package func setFanTargetRPM(index: Int, rpm: Int) throws {
        let clamped = max(0, rpm)
        let targetKey = fanKey(index, suffix: "Tg")
        let targetInfo = try? keyInfo(for: targetKey)

        if targetInfo?.dataType == "flt " {
            var floatValue = Float(clamped)
            let bytes = withUnsafeBytes(of: &floatValue) { Array($0) }
            try write(key: targetKey, dataType: "flt ", bytes: bytes)
            return
        }

        let raw = UInt16(clamped * 4)
        let bytes = [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        try write(key: targetKey, dataType: "fpe2", bytes: bytes)
    }

    private func writeUnsignedInt(key: String, value: Int) throws {
        if value <= Int(UInt8.max) {
            try write(key: key, dataType: "ui8", bytes: [UInt8(value)])
        } else if value <= Int(UInt16.max) {
            try write(key: key, dataType: "ui16", bytes: [UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
        } else {
            let bytes = [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff)
            ]
            try write(key: key, dataType: "ui32", bytes: bytes)
        }
    }

    private func read(key: String) throws -> SMCReadResult {
        let keyCode = try fourCC(key)

        var input = CSMCKeyData()
        var output = CSMCKeyData()
        input.key = keyCode
        input.data8 = UInt8(CSMC_CMD_READ_KEYINFO)
        try call(input: &input, output: &output)

        let keyInfo = output.keyInfo
        guard keyInfo.dataSize > 0 else {
            throw SMCError.invalidData("\(key) returned empty key info")
        }

        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = UInt8(CSMC_CMD_READ_BYTES)
        output = CSMCKeyData()
        try call(input: &input, output: &output)

        return SMCReadResult(
            bytes: bytes(from: output.bytes, count: Int(keyInfo.dataSize)),
            dataType: string(from: keyInfo.dataType),
            dataSize: Int(keyInfo.dataSize)
        )
    }

    private func keyInfo(for key: String) throws -> (dataSize: UInt32, dataType: String) {
        let keyCode = try fourCC(key)

        var input = CSMCKeyData()
        var output = CSMCKeyData()
        input.key = keyCode
        input.data8 = UInt8(CSMC_CMD_READ_KEYINFO)
        try call(input: &input, output: &output)

        return (output.keyInfo.dataSize, string(from: output.keyInfo.dataType))
    }

    private func write(key: String, dataType: String, bytes: [UInt8]) throws {
        let keyCode = try fourCC(key)

        var input = CSMCKeyData()
        var output = CSMCKeyData()
        input.key = keyCode
        input.data8 = UInt8(CSMC_CMD_READ_KEYINFO)
        try call(input: &input, output: &output)

        let keyInfo = output.keyInfo
        guard Int(keyInfo.dataSize) >= bytes.count else {
            throw SMCError.invalidData("\(key) expects \(keyInfo.dataSize) bytes but \(bytes.count) were provided")
        }

        input.keyInfo.dataSize = UInt32(bytes.count)
        input.keyInfo.dataType = fourCCPadded(dataType)
        input.data8 = UInt8(CSMC_CMD_WRITE_BYTES)
        copyBytes(bytes, into: &input.bytes)
        output = CSMCKeyData()
        try call(input: &input, output: &output)
    }

    private func call(input: inout CSMCKeyData, output: inout CSMCKeyData) throws {
        var outputSize = MemoryLayout<CSMCKeyData>.stride
        let result = withUnsafePointer(to: &input) { inputPointer in
            inputPointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<CSMCKeyData>.stride) { reboundInput in
                withUnsafeMutablePointer(to: &output) { outputPointer in
                    outputPointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<CSMCKeyData>.stride) { reboundOutput in
                        IOConnectCallStructMethod(
                            connection,
                            UInt32(CSMC_KERNEL_INDEX_SMC),
                            reboundInput,
                            MemoryLayout<CSMCKeyData>.stride,
                            reboundOutput,
                            &outputSize
                        )
                    }
                }
            }
        }

        guard result == KERN_SUCCESS else {
            throw SMCError.callFailed(result)
        }
    }

    private func fanKey(_ index: Int, suffix: String) -> String {
        "F\(index)\(suffix)"
    }
}

extension SMCConnection: FanHardwareControlling {}

private struct SMCReadResult {
    let bytes: [UInt8]
    let dataType: String
    let dataSize: Int
}


private func fourCC(_ string: String) throws -> UInt32 {
    guard string.utf8.count == 4 else {
        throw SMCError.invalidKey(string)
    }
    return string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}

private func fourCCPadded(_ string: String) -> UInt32 {
    let padded = string.padding(toLength: 4, withPad: " ", startingAt: 0)
    return padded.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
}

private func string(from code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
}

private func nativeFloat(from bytes: [UInt8]) -> Float {
    var value: Float = 0
    withUnsafeMutableBytes(of: &value) { destination in
        destination.copyBytes(from: bytes.prefix(4))
    }
    return value
}

private func copyBytes(_ bytes: [UInt8], into destination: inout (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) {
    withUnsafeMutableBytes(of: &destination) { buffer in
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        buffer.copyBytes(from: bytes.prefix(32))
    }
}

private func bytes(from tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8), count: Int) -> [UInt8] {
    withUnsafeBytes(of: tuple) { buffer in
        Array(buffer.prefix(count))
    }
}
