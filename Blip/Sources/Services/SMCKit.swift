import Foundation
import IOKit

// MARK: - SMC Interface for Apple Silicon

/// Lightweight SMC (System Management Controller) reader.
/// Used for fan RPM and thermal data on Apple Silicon Macs.
/// Supports both fpe2 (older Apple Silicon) and flt (M4+) data formats.
enum SMC {
    nonisolated(unsafe) private static var connection: io_connect_t = 0
    nonisolated(unsafe) private static var isOpen = false

    // SMC struct definitions matching kernel interface (exactly 80 bytes)
    struct SMCKeyData {
        struct Vers {
            var major: CUnsignedChar = 0
            var minor: CUnsignedChar = 0
            var build: CUnsignedChar = 0
            var reserved: CUnsignedChar = 0
            var release: CUnsignedShort = 0
        }

        struct PLimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: IOByteCount32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private static let kernelIndexSMC: UInt32 = 2

    // Well-known SMC data type FourCCs
    private static let typeFPE2 = fourCharCode("fpe2")
    private static let typeFLT  = fourCharCode("flt ")
    private static let typeSP78 = fourCharCode("sp78")
    private static let typeUI8  = fourCharCode("ui8 ")
    private static let typeUI16 = fourCharCode("ui16")
    private static let typeUI32 = fourCharCode("ui32")

    /// Whether the SMC connection has been validated with a known-good read.
    nonisolated(unsafe) private static var isValidated = false

    static func open() -> Bool {
        guard !isOpen else { return true }
        for serviceName in ["AppleSMC", "AppleARMSMC", "AppleSMCKeysEndpoint"] {
            let service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(serviceName)
            )
            guard service != 0 else { continue }
            let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
            IOObjectRelease(service)
            if result == kIOReturnSuccess {
                isOpen = true
                // Self-test: read fan count key to validate the connection
                if !isValidated {
                    if readKeyWithType("FNum") != nil {
                        isValidated = true
                    }
                    // Even if self-test fails, keep connection open —
                    // some keys may still work on this hardware
                }
                return true
            }
        }
        return false
    }

    /// Returns true if the SMC connection passed its self-test.
    static var available: Bool { isOpen && isValidated }

    static func close() {
        guard isOpen else { return }
        IOServiceClose(connection)
        isOpen = false
    }

    static func readFanCount() -> Int {
        guard let (_, bytes) = readKeyWithType("FNum"), !bytes.isEmpty else { return 0 }
        return Int(bytes[0])
    }

    static func readFanRPM(fan: Int) -> Int {
        readFanValue("F\(fan)Ac")
    }

    static func readFanMin(fan: Int) -> Int {
        readFanValue("F\(fan)Mn")
    }

    static func readFanMax(fan: Int) -> Int {
        readFanValue("F\(fan)Mx")
    }

    /// Reads a fan value, handling both fpe2 and flt data types
    private static func readFanValue(_ key: String) -> Int {
        guard let (dataType, bytes) = readKeyWithType(key), bytes.count >= 2 else { return 0 }
        if dataType == typeFLT && bytes.count >= 4 {
            // IEEE 754 float, little-endian byte order from SMC
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Int(Float(bitPattern: bits))
        } else {
            // fpe2: 14-bit integer, 2-bit fraction
            return Int(UInt16(bytes[0]) << 6 | UInt16(bytes[1]) >> 2)
        }
    }

    /// Read temperature in Celsius, handling sp78 and flt formats
    static func readTemperature(_ key: String) -> Double? {
        guard let (dataType, bytes) = readKeyWithType(key), bytes.count >= 2 else { return nil }
        let temp: Double
        if dataType == typeFLT && bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            temp = Double(Float(bitPattern: bits))
        } else {
            // sp78: signed 8.8 fixed point
            let raw = Int16(bytes[0]) << 8 | Int16(bytes[1])
            temp = Double(raw) / 256.0
        }
        guard temp > 0 && temp < 150 else { return nil }
        return temp
    }

    /// Read CPU temperature — tries common Apple Silicon and Intel SMC keys
    static func readCPUTemperature() -> Double? {
        for key in ["Tp09", "Tp0T", "Tp01", "TC0P", "TC0p"] {
            if let temp = readTemperature(key) { return temp }
        }
        return nil
    }

    /// Read GPU temperature — tries common SMC keys
    static func readGPUTemperature() -> Double? {
        for key in ["Tg05", "Tg0P", "TG0P", "Tg0p"] {
            if let temp = readTemperature(key) { return temp }
        }
        return nil
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        var result: UInt32 = 0
        for char in key.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    /// Reads an SMC key and returns both the data type and raw bytes
    private static func readKeyWithType(_ key: String) -> (dataType: UInt32, bytes: [UInt8])? {
        guard isOpen || open() else { return nil }

        var inputStruct = SMCKeyData()
        var outputStruct = SMCKeyData()

        inputStruct.key = fourCharCode(key)

        let inputSize = MemoryLayout<SMCKeyData>.stride
        let outputSize = MemoryLayout<SMCKeyData>.stride

        // First get key info
        inputStruct.data8 = 9 // kSMCGetKeyInfo
        var outputSizeVar = outputSize
        var result = IOConnectCallStructMethod(
            connection,
            kernelIndexSMC,
            &inputStruct,
            inputSize,
            &outputStruct,
            &outputSizeVar
        )
        guard result == kIOReturnSuccess else { return nil }

        let dataSize = Int(outputStruct.keyInfo.dataSize)
        let dataType = outputStruct.keyInfo.dataType
        inputStruct.keyInfo = outputStruct.keyInfo
        inputStruct.data8 = 5 // kSMCReadKey

        outputSizeVar = outputSize
        result = IOConnectCallStructMethod(
            connection,
            kernelIndexSMC,
            &inputStruct,
            inputSize,
            &outputStruct,
            &outputSizeVar
        )
        guard result == kIOReturnSuccess else { return nil }

        let mirror = Mirror(reflecting: outputStruct.bytes)
        var bytes: [UInt8] = []
        for child in mirror.children.prefix(dataSize) {
            if let byte = child.value as? UInt8 {
                bytes.append(byte)
            }
        }
        return (dataType, bytes)
    }
}
