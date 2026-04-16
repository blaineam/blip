import Foundation
import CryptoKit

/// RFC 6238 TOTP implementation for helper-app IPC authentication.
/// Both the main app and helper share a compiled-in secret derived
/// from a stable seed. This prevents casual injection/manipulation
/// of the TCP channel while keeping the implementation lightweight.
enum TOTP {
    private static let secret: SymmetricKey = {
        let seed = Data("com.blainemiller.Blip.HelperAuth.v1".utf8)
        let hash = SHA256.hash(data: seed)
        return SymmetricKey(data: hash)
    }()

    private static let period: UInt64 = 30
    private static let digits = 6

    /// Generate a TOTP token for the current time window.
    static func generate() -> String {
        let counter = UInt64(Date().timeIntervalSince1970) / period
        return code(for: counter)
    }

    /// Validate a TOTP token, allowing +/- 1 time step drift.
    static func validate(_ token: String) -> Bool {
        let counter = UInt64(Date().timeIntervalSince1970) / period
        for offset: Int64 in [-1, 0, 1] {
            let c = UInt64(max(0, Int64(counter) + offset))
            if code(for: c) == token {
                return true
            }
        }
        return false
    }

    private static func code(for counter: UInt64) -> String {
        var c = counter.bigEndian
        let data = withUnsafeBytes(of: &c) { Data($0) }
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: secret)
        let bytes = Array(hmac)
        let offset = Int(bytes[bytes.count - 1] & 0x0f)
        let value = (UInt32(bytes[offset]) & 0x7f) << 24 |
                    UInt32(bytes[offset + 1]) << 16 |
                    UInt32(bytes[offset + 2]) << 8 |
                    UInt32(bytes[offset + 3])
        let otp = value % 1_000_000
        return String(format: "%06d", otp)
    }
}
