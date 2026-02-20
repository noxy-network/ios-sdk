import Foundation
import Crypto

/// Decrypts encrypted notifications using Kyber decapsulation, HKDF key derivation, and AES-GCM.
public final class NoxyNotificationModule {
    private let deviceModule: NoxyDeviceModule
    private let kyber: NoxyKyberProvider

    public init(deviceModule: NoxyDeviceModule, kyber: NoxyKyberProvider = NoxyKyberProvider()) {
        self.deviceModule = deviceModule
        self.kyber = kyber
    }

    /// Decrypt notification envelope to plain payload (JSON object as [String: Any])
    public func decryptNotification(_ envelope: NoxyEncryptedNotification) async throws -> [String: Any]? {
        guard let keys = try await deviceModule.loadDevicePrivateKeys() else {
            throw NoxyError.general("Device cannot decrypt notification")
        }

        let sharedSecret: Data
        do {
            sharedSecret = try kyber.decapsulate(secretKey: keys.pqPrivateKey, ciphertext: envelope.kyberCt)
        } catch {
            throw NoxyError.general("Kyber decapsulation failed: \(error)")
        }

        // HKDF salt: try both 32-zero and empty for cross-SDK compatibility.
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.nonce), ciphertext: envelope.ciphertextWithoutTag, tag: envelope.tag)
        let salts: [Data] = [Data(repeating: 0, count: 32), Data()]
        var plaintext: Data?
        for salt in salts {
            let aesKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: sharedSecret),
                salt: salt,
                info: Data(),
                outputByteCount: 32
            )
            if let pt = try? AES.GCM.open(sealedBox, using: aesKey) {
                plaintext = pt
                break
            }
        }
        guard let plaintext else {
            throw NoxyError.general("AES-GCM decrypt failed: authenticationFailure")
        }

        guard let json = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            return nil
        }
        return json
    }
}
