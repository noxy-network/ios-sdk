import Foundation

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

/// Main Noxy client for the [Noxy Decision Layer](https://noxy.network): wallet identity, relay connection,
/// encrypted decision requests, and outcomes (approve/reject).
public final class NoxyClient {
    private let identity: NoxyIdentity
    private let networkOptions: NoxyNetworkOptions
    private let deviceModule: NoxyDeviceModule
    private let networkModule: NoxyNetworkModule
    private let decisionCryptoModule: NoxyDecisionCryptoModule

    private var apnsToken: Data?
    private var decisionHandler: ((_ messageId: String?, _ decision: [String: Any]) -> Void)?

    public init(
        identity: NoxyIdentity,
        network: NoxyNetworkOptions,
        storage: NoxyStorage = NoxyStorage()
    ) {
        self.identity = identity
        self.networkOptions = network
        self.deviceModule = NoxyDeviceModule(storage: storage)
        self.networkModule = NoxyNetworkModule(options: network)
        self.decisionCryptoModule = NoxyDecisionCryptoModule(deviceModule: self.deviceModule)
    }

    public var address: WalletAddress { identity.address }
    public var isDeviceActive: Bool { deviceModule.isRevoked == false }
    public var isRelayConnected: Bool { networkModule.isConnected }
    public var isNetworkReady: Bool { networkModule.isReady }

    /// Effective APNs token: from `setApnsToken(_:)` as hex, or from `NoxyNetworkOptions.apnToken`.
    /// When set, enables offline wake-up; when nil, online-only.
    private var effectiveApnToken: String? {
        if let data = apnsToken, !data.isEmpty { return data.hexString }
        return networkOptions.apnToken
    }

    /// Initialize: load or create device, connect to network, authenticate.
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
            throw NoxyError.general("Unable to rotate keys")
        }
        try await deviceModule.rotateKeys()
        guard let pk = deviceModule.publicKey, let pqPk = deviceModule.pqPublicKey else {
            throw NoxyError.general("Unable to rotate keys")
        }
        try await networkModule.rotateDeviceKeys(
            newPubkeys: (pk, pqPk),
            walletAddress: address,
            signature: sig
        )
    }

    /// Register APNs device token for silent wake-up when the app is backgrounded.
    public func setApnsToken(_ token: Data) {
        apnsToken = token
    }

    /// Subscribe to encrypted decision requests from the relay.
    /// - Parameters:
    ///   - handler: Called with `(messageId, decision)` where `messageId` is the relay stream id (use for outcomes when JSON has no `decision_id`), and `decision` is the decrypted JSON payload.
    /// After each successful decrypt, a delivery ``sendDecisionAck`` is sent when a decision id is known (payload or relay `message_id`).
    public func on(handler: @escaping (_ messageId: String?, _ decision: [String: Any]) -> Void) async throws {
        decisionHandler = handler
        _ = try await deviceModule.loadDevicePrivateKeys()
        try await networkModule.subscribeToDecisions(
            handler: { [weak self] envelope, relayMessageId in
                guard let self else { return }
                await self.deliverDecision(envelope: envelope, relayMessageId: relayMessageId, notifyUser: handler)
            },
            apnToken: effectiveApnToken
        )
    }

    private func deliverDecision(
        envelope: NoxyEncryptedDecision,
        relayMessageId: String?,
        notifyUser: ((_ messageId: String?, _ decision: [String: Any]) -> Void)?
    ) async {
        do {
            guard let decrypted = try await decisionCryptoModule.decryptDecision(envelope) else {
                #if DEBUG
                print("[NoxySDK][Client] decryptDecision returned nil (cannot decrypt for this device / bad envelope)")
                #endif
                return
            }
            #if DEBUG
            let keys = decrypted.keys.sorted().joined(separator: ", ")
            print("[NoxySDK][Client] decision decrypted message_id=\(relayMessageId ?? "nil") keys=[\(keys)]")
            #endif
            // Deliver to the app first. Do not await sendDecisionAck here: it uses sendAndWait on the same
            // bidirectional stream whose responses are only consumed by processResponseStream. While this
            // handler runs, that loop cannot read the ACK response — deadlock (and Approve/Reject hang).
            notifyUser?(relayMessageId, decrypted)
            if let ackId = Self.deliveryAckDecisionId(from: decrypted, relayMessageId: relayMessageId) {
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.networkModule.sendDecisionAck(decisionId: ackId)
                }
            }
        } catch {
            #if DEBUG
            print("[NoxySDK][Client] decryptDecision failed: \(error)")
            #endif
        }
    }

    private static func deliveryAckDecisionId(from payload: [String: Any], relayMessageId: String?) -> String? {
        if let s = relayMessageId, !s.isEmpty { return s }
        if let s = payload["decision_id"] as? String, !s.isEmpty { return s }
        if let s = payload["decisionId"] as? String, !s.isEmpty { return s }
        if let s = payload["message_id"] as? String, !s.isEmpty { return s }
        return nil
    }

    /// Send approve/reject to the relay for a decision (e.g. after the user taps a notification action).
    public func sendDecisionOutcome(
        decisionId: String,
        outcome: NoxyDecisionChoice,
        receivedAt: UInt64? = nil
    ) async throws {
        try await networkModule.sendDecisionOutcome(decisionId: decisionId, outcome: outcome, receivedAt: receivedAt)
    }

    /// Optional extra delivery ack (normally acks are sent automatically after each decrypted decision).
    public func sendDecisionAck(decisionId: String, receivedAt: UInt64? = nil) async throws {
        try await networkModule.sendDecisionAck(decisionId: decisionId, receivedAt: receivedAt)
    }

    /// Check if `userInfo` is a Noxy wake-up (`aps.content-available: 1`).
    public static func isNoxyWakeUp(userInfo: [AnyHashable: Any]) -> Bool {
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return false }
        let contentAvailable = aps["content-available"]
        return (contentAvailable as? Int == 1) || (contentAvailable as? NSNumber)?.intValue == 1
    }

    /// Handle APNs wake-up: reconnect and resume the decision stream.
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
        guard decisionHandler != nil else {
            completion(.noData)
            return
        }
        Task {
            var result: NoxyWakeUpResult = .noData
            defer { completion(result) }

            if networkModule.isConnected {
                await networkModule.disconnectForReconnect()
            }
            guard let device = try? await deviceModule.load(identityId: identity.address, appId: networkOptions.appId),
                  !device.isRevoked else {
                return
            }
            guard let _ = try? await deviceModule.loadDevicePrivateKeys() else { return }

            let maxAttempts = 3
            for attempt in 1...maxAttempts {
                do {
                    try await networkModule.connect()
                    _ = try await networkModule.authenticateDevice(device)
                    try await networkModule.subscribeToDecisions(
                        handler: { [weak self] envelope, relayMessageId in
                            guard let self else { return }
                            Task {
                                await self.deliverDecision(envelope: envelope, relayMessageId: relayMessageId) { messageId, decision in
                                    result = .newData
                                    let handler = self.decisionHandler
                                    DispatchQueue.main.async { handler?(messageId, decision) }
                                }
                            }
                        },
                        apnToken: effectiveApnToken
                    )
                    break
                } catch {
                    if attempt < maxAttempts {
                        await networkModule.disconnectForReconnect()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    } else {
                        result = .failed
                        return
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    /// Disconnect from relay
    public func close() async {
        await networkModule.disconnect()
    }
}

/// Result for APNs wake-up fetch. Map to `UIBackgroundFetchResult` for the system completion handler.
public enum NoxyWakeUpResult {
    case newData
    case noData
    case failed
}

public enum NoxyError: Error {
    case initializationFailed(String)
    case general(String)
}
