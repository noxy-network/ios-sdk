import Foundation

/// Main Noxy client. Lightweight orchestrator: no state machine, no DI.
public final class NoxyClient {
    private let identity: NoxyIdentity
    private let networkOptions: NoxyNetworkOptions
    private let deviceModule: NoxyDeviceModule
    private let networkModule: NoxyNetworkModule
    private let notificationModule: NoxyNotificationModule

    public init(
        identity: NoxyIdentity,
        network: NoxyNetworkOptions,
        storage: NoxyStorage = NoxyStorage()
    ) {
        self.identity = identity
        self.networkOptions = network
        self.deviceModule = NoxyDeviceModule(storage: storage)
        self.networkModule = NoxyNetworkModule(options: network)
        self.notificationModule = NoxyNotificationModule(deviceModule: self.deviceModule)
    }

    public var address: WalletAddress { identity.address }
    public var isDeviceActive: Bool { deviceModule.isRevoked == false }
    public var isRelayConnected: Bool { networkModule.isConnected }
    public var isNetworkReady: Bool { networkModule.isReady }

    /// Initialize: load or create device, connect to network, authenticate.
    /// Only registers (announces) the device on the relay when the authenticate response
    /// contains requires_registration: true (e.g. relay does not know the device).
    public func initialize() async throws {
        try await networkModule.connect()

        var device: NoxyDevice?
        if let loaded = try await deviceModule.load(identityId: identity.address, appId: networkOptions.appId) {
            device = loaded
        } else {
            device = try await deviceModule.register(
                appId: networkOptions.appId,
                identityId: identity.address,
                identitySigner: identity.signer
            )
        }

        guard let dev = device else { throw NoxyError.initializationFailed("No device") }

        let requiresRegistration = try await networkModule.authenticateDevice(dev)

        if requiresRegistration {
            guard let sig = dev.identitySignature else {
                throw NoxyError.initializationFailed("Device has no identity signature for relay registration")
            }
            try await networkModule.announceDevice(
                devicePubkeys: (dev.publicKey, dev.pqPublicKey),
                walletAddress: dev.identityId,
                signature: sig
            )
        }
    }

    /// Revoke device locally and on relay
    public func revokeDevice() async throws {
        guard let sig = try await deviceModule.getDeviceSignature() else {
            throw NoxyError.general("Unable to revoke device")
        }
        try await deviceModule.revoke()
        try await networkModule.revokeDevice(walletAddress: address, signature: sig)
    }

    /// Rotate device keys locally and on relay
    public func rotateKeys() async throws {
        guard let sig = try await deviceModule.getDeviceSignature() else {
            throw NoxyError.general("Unable to rotate device keys")
        }
        try await deviceModule.rotateKeys()
        guard let pk = deviceModule.publicKey, let pqPk = deviceModule.pqPublicKey else {
            throw NoxyError.general("Unable to rotate device keys")
        }
        try await networkModule.rotateDeviceKeys(
            newPubkeys: (pk, pqPk),
            walletAddress: address,
            signature: sig
        )
    }

    /// Subscribe to notifications. Loads device private keys first.
    public func on(handler: @escaping ([String: Any]) -> Void) async throws {
        _ = try await deviceModule.loadDevicePrivateKeys()
        try await networkModule.subscribeToNotifications { [weak self] envelope in
            guard let self else { return }
            do {
                if let decrypted = try await self.notificationModule.decryptNotification(envelope) {
                    handler(decrypted)
                }
            } catch {
                // Decryption failed; silently ignored
            }
        }
    }

    /// Disconnect from relay
    public func close() async {
        await networkModule.disconnect()
    }
}

public enum NoxyError: Error {
    case initializationFailed(String)
    case general(String)
}
