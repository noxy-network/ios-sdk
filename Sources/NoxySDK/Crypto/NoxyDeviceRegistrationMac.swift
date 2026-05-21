import Foundation
import CryptoKit

/// Canonical registration HMAC — must match relay `device_registration_mac_message_utf8`.
public enum NoxyDeviceRegistrationMac {
    private static let prefix = "NOXY_DEVICE_REGISTER_V1"
    private static let sep: Character = "\u{001f}"

    public static func sign(
        secret: String,
        appId: String,
        identityType: NoxyRelayIdentityType,
        logicalIdentityId: String,
        publicKey: Data,
        pqPublicKey: Data,
        deviceType: String
    ) throws -> Data {
        let pkHex = Self.sha256Hex(publicKey)
        let pqHex = Self.sha256Hex(pqPublicKey)
        let it = identityType.rawValue
        let msg = "\(prefix)\(sep)\(appId)\(sep)\(it)\(sep)\(logicalIdentityId)\(sep)\(pkHex)\(sep)\(pqHex)\(sep)\(deviceType)"
        let keyData = Data(secret.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let key = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: key)
        return Data(mac)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
