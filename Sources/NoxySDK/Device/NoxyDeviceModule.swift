import Foundation
import Crypto
import KeccakSwift

private let deviceVersion = "noxy-device/v1"

/// Device management: generate keys, register, load, revoke, rotate
public final class NoxyDeviceModule {
    private let storage: NoxyStorage
    private let kyber: NoxyKyberProvider
    private var currentDevice: NoxyDevice?

    public init(storage: NoxyStorage = NoxyStorage(), kyber: NoxyKyberProvider = NoxyKyberProvider()) {
        self.storage = storage
        self.kyber = kyber
    }

    public var publicKey: Data? { currentDevice?.publicKey }
    public var pqPublicKey: Data? { currentDevice?.pqPublicKey }
    public var isRevoked: Bool? { currentDevice?.isRevoked }
    public var device: NoxyDevice? { currentDevice }

    private func storageKey(device: NoxyDevice) -> String {
        "\(device.appId)_\(device.identityId)"
    }

    private func devicesKey(identityId: WalletAddress) -> String {
        "devices_\(identityId)"
    }

    /// Build hash for identity signature (keccak256 for relay verification).
    public func buildIdentitySignatureHash(device: NoxyDevice) throws -> Data {
        var payload = Data()
        payload.append(Data(deviceVersion.utf8))
        payload.append(Data(device.appId.utf8))
        payload.append(Data(device.identityId.utf8))
        payload.append(device.publicKey)
        payload.append(device.pqPublicKey)
        var issuedAtBytes = [UInt8](repeating: 0, count: 8)
        withUnsafeBytes(of: device.issuedAt.bigEndian) { buf in
            for i in 0..<8 { issuedAtBytes[i] = buf[i] }
        }
        payload.append(Data(issuedAtBytes))
        return try Keccak.hash(data: payload, rate: .keccak(.rate256), outputSize: .bytes(32))
    }

    /// Generate Ed25519 + ML-KEM keypairs
    private func generateKeys() -> (keyPair: (publicKey: Data, privateKey: Data), pqKeyPair: (publicKey: Data, secretKey: Data)) {
        let keyPair = Curve25519.Signing.PrivateKey()
        let pqKeyPair = kyber.keypair()
        return (
            (keyPair.publicKey.rawRepresentation, keyPair.rawRepresentation),
            (pqKeyPair.publicKey, pqKeyPair.secretKey)
        )
    }

    /// Load device for identity
    public func load(identityId: WalletAddress, appId: String? = nil) async throws -> NoxyDevice? {
        let key = devicesKey(identityId: identityId)
        guard let data = try storage.load(key: key) else {
            return nil
        }
        let devices = try JSONDecoder().decode([NoxyDeviceCodable].self, from: data)
        let device = devices.first { !$0.isRevoked && (appId == nil || $0.appId == appId!) }
        if let d = device?.toDevice() {
            currentDevice = d
            return d
        }
        currentDevice = nil
        return nil
    }

    /// Register new device
    public func register(
        appId: String,
        identityId: WalletAddress,
        identitySigner: SignerClosure?
    ) async throws -> NoxyDevice {
        let (keyPair, pqKeyPair) = generateKeys()
        let issuedAt = UInt64(Date().timeIntervalSince1970 * 1000)

        var device = NoxyDevice(
            identityId: identityId,
            appId: appId,
            isRevoked: false,
            issuedAt: issuedAt,
            publicKey: keyPair.publicKey,
            pqPublicKey: pqKeyPair.publicKey,
            identitySignature: nil
        )

        let hash = try buildIdentitySignatureHash(device: device)
        if let signer = identitySigner {
            let sig = try await signer(hash)
            device.identitySignature = sig.bytes
        }

        currentDevice = device
        try await persistDevice(device)
        try await persistPrivateKeys(NoxyDevicePrivateKeys(privateKey: keyPair.privateKey, pqPrivateKey: pqKeyPair.secretKey))
        return device
    }

    /// Load device private keys
    public func loadDevicePrivateKeys() async throws -> NoxyDevicePrivateKeys? {
        guard let device = currentDevice else { return nil }
        let key = "keys_\(storageKey(device: device))"
        guard let data = try storage.load(key: key) else { return nil }
        let keys = try JSONDecoder().decode(NoxyDevicePrivateKeysCodable.self, from: data)
        return NoxyDevicePrivateKeys(privateKey: Data(keys.privateKey), pqPrivateKey: Data(keys.pqPrivateKey))
    }

    /// Revoke device locally
    public func revoke() async throws {
        guard var device = currentDevice else { return }
        device.isRevoked = true
        currentDevice = device
        try await persistDevice(device)
    }

    /// Rotate device keys
    public func rotateKeys() async throws {
        guard let device = currentDevice else { return }
        let (keyPair, pqKeyPair) = generateKeys()

        let updatedDevice = NoxyDevice(
            identityId: device.identityId,
            appId: device.appId,
            isRevoked: device.isRevoked,
            issuedAt: device.issuedAt,
            publicKey: keyPair.publicKey,
            pqPublicKey: pqKeyPair.publicKey,
            identitySignature: device.identitySignature
        )
        currentDevice = updatedDevice

        try await persistDevice(updatedDevice)
        try await persistPrivateKeys(NoxyDevicePrivateKeys(privateKey: keyPair.privateKey, pqPrivateKey: pqKeyPair.secretKey))
    }

    /// Get device signature for auth (signs domain + appId + identityId + timestamp + nonce)
    public func getDeviceSignature() async throws -> Data? {
        guard let device = currentDevice else { return nil }
        guard let keys = try await loadDevicePrivateKeys() else { return nil }

        var payload = Data()
        payload.append(Data(deviceVersion.utf8))
        payload.append(Data(device.appId.utf8))
        payload.append(Data(device.identityId.utf8))
        var ts = UInt64(Date().timeIntervalSince1970 * 1000).bigEndian
        payload.append(Data(bytes: &ts, count: 8))
        payload.append(Data((0..<16).map { _ in UInt8.random(in: 0...255) }))

        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keys.privateKey)
        return try privateKey.signature(for: payload)
    }

    private func persistDevice(_ device: NoxyDevice) async throws {
        let key = devicesKey(identityId: device.identityId)
        var devices: [NoxyDeviceCodable]
        if let data = try storage.load(key: key) {
            devices = try JSONDecoder().decode([NoxyDeviceCodable].self, from: data)
            devices.removeAll { $0.appId == device.appId && $0.identityId == device.identityId }
        } else {
            devices = []
        }
        devices.append(NoxyDeviceCodable(from: device))
        try storage.save(key: key, data: try JSONEncoder().encode(devices))
    }

    private func persistPrivateKeys(_ keys: NoxyDevicePrivateKeys) async throws {
        guard let device = currentDevice else { return }
        let key = "keys_\(storageKey(device: device))"
        let codable = NoxyDevicePrivateKeysCodable(privateKey: Array(keys.privateKey), pqPrivateKey: Array(keys.pqPrivateKey))
        try storage.save(key: key, data: try JSONEncoder().encode(codable))
    }
}

private struct NoxyDeviceCodable: Codable {
    let identityId: String
    let appId: String
    let isRevoked: Bool
    let issuedAt: UInt64
    let publicKey: Data
    let pqPublicKey: Data
    let identitySignature: Data?

    init(from d: NoxyDevice) {
        identityId = d.identityId
        appId = d.appId
        isRevoked = d.isRevoked
        issuedAt = d.issuedAt
        publicKey = d.publicKey
        pqPublicKey = d.pqPublicKey
        identitySignature = d.identitySignature
    }

    func toDevice() -> NoxyDevice {
        NoxyDevice(
            identityId: identityId,
            appId: appId,
            isRevoked: isRevoked,
            issuedAt: issuedAt,
            publicKey: publicKey,
            pqPublicKey: pqPublicKey,
            identitySignature: identitySignature
        )
    }
}

private struct NoxyDevicePrivateKeysCodable: Codable {
    let privateKey: [UInt8]
    let pqPrivateKey: [UInt8]
}
