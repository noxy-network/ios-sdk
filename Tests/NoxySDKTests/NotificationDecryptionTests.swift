import XCTest
@testable import NoxySDK
import Crypto

/// Verifies notification decryption: Kyber decapsulate → HKDF → AES-GCM decrypt
final class NotificationDecryptionTests: XCTestCase {

    func testDecryptNotificationRoundTrip() async throws {
        let kyber = NoxyKyberProvider()
        let storage = NoxyStorage(serviceName: "noxy-test-\(UUID().uuidString)")
        let deviceModule = NoxyDeviceModule(storage: storage, kyber: kyber)

        _ = try await deviceModule.register(
            appId: "test-app",
            identityId: "0xtest",
            identitySigner: nil
        )

        guard let devicePqPublicKey = deviceModule.pqPublicKey else {
            XCTFail("Device should have pq public key")
            return
        }

        let notificationModule = NoxyNotificationModule(deviceModule: deviceModule, kyber: kyber)

        let plainPayload: [String: Any] = ["type": "test", "title": "Hello", "message": "World"]
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

        let envelope = NoxyEncryptedNotification(
            kyberCt: kyberCt,
            nonce: Data(nonce),
            ciphertext: ciphertext
        )

        let decrypted = try await notificationModule.decryptNotification(envelope)
        XCTAssertNotNil(decrypted)
        XCTAssertEqual(decrypted?["type"] as? String, "test")
        XCTAssertEqual(decrypted?["title"] as? String, "Hello")
        XCTAssertEqual(decrypted?["message"] as? String, "World")
    }
}
