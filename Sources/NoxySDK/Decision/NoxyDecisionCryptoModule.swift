import Foundation
import Crypto

/// Decrypts encrypted decision payloads from the Noxy Decision Layer (Kyber + HKDF + AES-GCM).
public final class NoxyDecisionCryptoModule {
    private let deviceModule: NoxyDeviceModule
    private let kyber: NoxyKyberProvider

    public init(deviceModule: NoxyDeviceModule, kyber: NoxyKyberProvider = NoxyKyberProvider()) {
        self.deviceModule = deviceModule
        self.kyber = kyber
    }

    /// Decrypt a decision event envelope to a plain JSON object (e.g. `decision_id`, `title`, `body`).
    public func decryptDecision(_ envelope: NoxyEncryptedDecision) async throws -> [String: Any]? {
        guard let keys = try await deviceModule.loadDevicePrivateKeys() else {
            throw NoxyError.general("Device cannot decrypt decision")
        }

        let sharedSecret: Data
        do {
            sharedSecret = try kyber.decapsulate(secretKey: keys.pqPrivateKey, ciphertext: envelope.kyberCt)
        } catch {
            throw NoxyError.general("Kyber decapsulation failed: \(error)")
        }

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
