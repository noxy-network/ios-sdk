import XCTest
@testable import NoxySDK
import Crypto

/// Verifies decision payload decryption: Kyber decapsulate → HKDF → AES-GCM decrypt
final class DecisionDecryptionTests: XCTestCase {

    func testDecryptDecisionRoundTrip() async throws {
        let kyber = NoxyKyberProvider()
        let storage = NoxyStorage(serviceName: "noxy-test-\(UUID().uuidString)")
        let deviceModule = NoxyDeviceModule(storage: storage, kyber: kyber)

        let identity = NoxyIdentity.eoa(NoxyEoaWalletIdentity(address: "0xtest") { _ in
            Signature(bytes: Data(repeating: 1, count: 65))
        })

        _ = try await deviceModule.register(appId: "test-app", identity: identity, appSigningSecret: "test-app-signing-secret")

        guard let devicePqPublicKey = deviceModule.pqPublicKey else {
            XCTFail("Device should have pq public key")
            return
        }

        let decisionCrypto = NoxyDecisionCryptoModule(deviceModule: deviceModule, kyber: kyber)

        let plainPayload: [String: Any] = ["decision_id": "d1", "title": "Hello", "body": "Approve?"]
        let plainData = try JSONSerialization.data(withJSONObject: plainPayload)

        let (kyberCt, sharedSecret) = try kyber.encapsulate(publicKey: devicePqPublicKey)
        let aesKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecret),
            outputByteCount: 32
        )
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plainData, using: aesKey, nonce: nonce)
        var ciphertext = sealedBox.ciphertext
        ciphertext.append(contentsOf: sealedBox.tag)

        let envelope = NoxyEncryptedDecision(
            kyberCt: kyberCt,
            nonce: Data(nonce),
            ciphertext: ciphertext
        )

        let decrypted = try await decisionCrypto.decryptDecision(envelope)
        XCTAssertNotNil(decrypted)
        XCTAssertEqual(decrypted?["decision_id"] as? String, "d1")
        XCTAssertEqual(decrypted?["title"] as? String, "Hello")
        XCTAssertEqual(decrypted?["body"] as? String, "Approve?")
    }
}
