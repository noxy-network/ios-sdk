import Foundation

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

/// Main Noxy client. Lightweight orchestrator: no state machine, no DI.
public final class NoxyClient {
    private let identity: NoxyIdentity
    private let networkOptions: NoxyNetworkOptions
    private let deviceModule: NoxyDeviceModule
    private let networkModule: NoxyNetworkModule
    private let notificationModule: NoxyNotificationModule

    private var apnsToken: Data?
    private var notificationHandler: (([String: Any]) -> Void)?

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

    /// Effective APNs token: from setApnsToken(Data) as hex, or from NoxyNetworkOptions.apnToken.
    /// When set, enables offline wake-up pushes; when nil, online-only.
    private var effectiveApnToken: String? {
        if let data = apnsToken, !data.isEmpty { return data.hexString }
        return networkOptions.apnToken
    }

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
                signature: sig,
                apnToken: effectiveApnToken
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

    /// Register APNs device token for silent wake-up pushes when app is backgrounded.
    /// Call when `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` fires.
    public func setApnsToken(_ token: Data) {
        apnsToken = token
    }

    /// Subscribe to notifications. Loads device private keys first.
    public func on(handler: @escaping ([String: Any]) -> Void) async throws {
        notificationHandler = handler
        _ = try await deviceModule.loadDevicePrivateKeys()
        try await networkModule.subscribeToNotifications(
            handler: { [weak self] envelope in
                guard let self else { return }
                do {
                    if let decrypted = try await self.notificationModule.decryptNotification(envelope) {
                        handler(decrypted)
                    }
                } catch {
                    // Decryption failed; silently ignored
                }
            },
            apnToken: effectiveApnToken
        )
    }

    /// Check if userInfo is a Noxy wake-up (relay sends `{"aps": {"content-available": 1}}`).
    public static func isNoxyWakeUp(userInfo: [AnyHashable: Any]) -> Bool {
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return false }
        let contentAvailable = aps["content-available"]
        return (contentAvailable as? Int == 1) || (contentAvailable as? NSNumber)?.intValue == 1
    }

    /// Handle APNs wake-up: reconnect to relay and fetch notifications.
    /// Call from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
    /// If userInfo is provided, only proceeds when it matches relay wake format (`aps.content-available: 1`).
    /// Requires "Remote notifications" background mode.
    public func handleWakeUpNotification(
        userInfo: [AnyHashable: Any]? = nil,
        fetchCompletionHandler completion: @escaping (NoxyWakeUpResult) -> Void
    ) {
        if let info = userInfo, !Self.isNoxyWakeUp(userInfo: info) {
            completion(.noData)
            return
        }
        performWakeUpFetch(completion: completion)
    }

    private func performWakeUpFetch(completion: @escaping (NoxyWakeUpResult) -> Void) {
        guard notificationHandler != nil else {
            completion(.noData)
            return
        }
        Task {
            var result: NoxyWakeUpResult = .noData
            defer { completion(result) }

            // Disconnect quickly to allow fast reconnect (relay expects new connection soon)
            await networkModule.disconnectForReconnect()
            guard let device = try? await deviceModule.load(identityId: identity.address, appId: networkOptions.appId),
                  !device.isRevoked else {
                return
            }
            guard let _ = try? await deviceModule.loadDevicePrivateKeys() else { return }

            do {
                // 1. Establish live gRPC connection (reconnect)
                try await networkModule.connect()
                // 2. Authenticate device again to establish session
                _ = try await networkModule.authenticateDevice(device)
                // 3. Subscribe for notifications over the live connection
                try await networkModule.subscribeToNotifications(
                    handler: { [weak self] envelope in
                        guard let self else { return }
                        Task {
                            do {
                                if let decrypted = try await self.notificationModule.decryptNotification(envelope) {
                                    result = .newData
                                    let payload = decrypted
                                    let handler = self.notificationHandler
                                    DispatchQueue.main.async { handler?(payload) }
                                }
                            } catch { /* ignore */ }
                        }
                    },
                    apnToken: effectiveApnToken
                )
            } catch {
                result = .failed
                return
            }

            try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s to receive pushes
        }
    }

    /// Disconnect from relay
    public func close() async {
        await networkModule.disconnect()
    }
}

/// Result for APNs wake-up fetch. Map to `UIBackgroundFetchResult` when calling the system completion handler.
public enum NoxyWakeUpResult {
    case newData
    case noData
    case failed
}

public enum NoxyError: Error {
    case initializationFailed(String)
    case general(String)
}
