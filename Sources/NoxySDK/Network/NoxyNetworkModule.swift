import Foundation
import GRPC
import NIO
import NIOPosix

/// Network module: gRPC-based relay communication via bidirectional HandleMessage stream.
public final class NoxyNetworkModule: @unchecked Sendable {
    private let options: NoxyNetworkOptions
    private var channel: GRPCChannel?
    private var eventLoopGroup: EventLoopGroup?
    private var streamCall: GRPCAsyncBidirectionalStreamingCall<Noxy_Device_DeviceRequest, Noxy_Device_DeviceResponse>?
    private var responseTask: Task<Void, Error>?
    private var _sessionId: String?
    private var _networkDeviceId: String?
    private var pendingRequests: [String: CheckedContinuation<Noxy_Device_DeviceResponse, Error>] = [:]
    private var decisionHandler: ((NoxyEncryptedDecision, String?) async -> Void)?
    private let lock = NSLock()
    private let connectionLock = NSLock()

    public init(options: NoxyNetworkOptions) {
        self.options = options
    }

    public var isConnected: Bool { channel != nil }
    public var isReady: Bool { isConnected && currentSessionId != nil && currentDeviceId != nil }
    public var currentSessionId: String? { _sessionId }
    public var currentDeviceId: String? { _networkDeviceId }

    private func setSessionId(_ v: String?) { _sessionId = v }
    private func setNetworkDeviceId(_ v: String?) { _networkDeviceId = v }

    /// Parse relay URL into host and port. Requires HTTPS.
    private func parseRelayURL(_ urlString: String) throws -> (host: String, port: Int) {
        guard let url = URL(string: urlString),
              let host = url.host, !host.isEmpty else {
            throw NoxyError.general("Invalid relay URL: \(urlString)")
        }
        guard url.scheme?.lowercased() == "https" else {
            throw NoxyError.general("Relay URL must use HTTPS")
        }
        let port = url.port ?? 443
        return (host, port)
    }

    /// Connect to relay via gRPC (always TLS).
    /// Waits for any in-progress disconnect to finish before connecting (avoids race conditions).
    public func connect() async throws {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        let (host, port) = try parseRelayURL(options.relayUrl)
        let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
        let tlsConfig = GRPCTLSConfiguration.makeClientDefault(compatibleWith: group)
        let transportSecurity: GRPCChannelPool.Configuration.TransportSecurity = .tls(tlsConfig)

        eventLoopGroup = group

        let ch = try GRPCChannelPool.with(
            target: .host(host, port: port),
            transportSecurity: transportSecurity,
            eventLoopGroup: group
        )
        channel = ch

        let client = Noxy_Device_DeviceServiceAsyncClient(
            channel: ch,
            defaultCallOptions: CallOptions(),
            interceptors: nil
        )

        let call = client.makeHandleMessageCall()
        streamCall = call

        responseTask = Task { [weak self] in
            try await self?.processResponseStream(call)
        }
    }

    private func processResponseStream(_ call: GRPCAsyncBidirectionalStreamingCall<Noxy_Device_DeviceRequest, Noxy_Device_DeviceResponse>) async throws {
        for try await response in call.responseStream {
            switch response.payload {
            case .decisionEvent(let ev):
                let envelope = NoxyEncryptedDecision(
                    kyberCt: ev.kyberCt,
                    nonce: ev.nonce,
                    ciphertext: ev.ciphertext
                )
                let relayMessageId = response.hasMessageID ? response.messageID : nil
                
                let mid = relayMessageId ?? "(none)"
                let rid = response.requestID.isEmpty ? "(none)" : response.requestID
                print("[NoxySDK][Network] decisionEvent received request_id=\(rid) message_id=\(mid) kyber=\(ev.kyberCt.count)B nonce=\(ev.nonce.count)B ciphertext=\(ev.ciphertext.count)B handler=\(decisionHandler != nil ? "yes" : "no")")
                
                if let handler = decisionHandler {
                    await handler(envelope, relayMessageId)
                } else {
                    
                    print("[NoxySDK][Network] decisionEvent dropped: no subscribe handler yet")
                   
                }
            case .authenticate(let auth):
                if auth.hasDeviceID { setNetworkDeviceId(auth.deviceID) }
                if auth.hasSessionID { setSessionId(auth.sessionID) }
                resumePending(requestID: response.requestID, response: response)
            case .registerDevice(let reg):
                setNetworkDeviceId(reg.deviceID)
                setSessionId(reg.sessionID)
                resumePending(requestID: response.requestID, response: response)
            case .subscribeDecisions, .revokeDevice, .rotateDeviceKeys, .decisionOutcome, .decisionAck:
                resumePending(requestID: response.requestID, response: response)
            case .decisionRouted:
                break
            case .error(let err):
                if !response.requestID.isEmpty {
                    resumePending(requestID: response.requestID, error: NoxyError.general("Relay error: \(err.code) \(err.message)"))
                }
            case .none:
                break
            }
        }
    }

    private func resumePending(requestID: String, response: Noxy_Device_DeviceResponse) {
        lock.lock()
        let cont = pendingRequests.removeValue(forKey: requestID)
        lock.unlock()
        cont?.resume(returning: response)
    }

    private func resumePending(requestID: String, error: Error) {
        lock.lock()
        let cont = pendingRequests.removeValue(forKey: requestID)
        lock.unlock()
        cont?.resume(throwing: error)
    }

    /// Send request and wait for response (by request_id)
    private func sendAndWait(_ request: Noxy_Device_DeviceRequest) async throws -> Noxy_Device_DeviceResponse {
        guard let stream = streamCall else { throw NoxyError.general("Not connected") }
        let requestID = request.requestID.isEmpty ? UUID().uuidString : request.requestID

        var req = request
        req.requestID = requestID
        req.appID = options.appId
        if req.timestamp == 0 { req.timestamp = UInt64(Date().timeIntervalSince1970 * 1000) }
        if req.nonce.isEmpty { req.nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) }) }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Noxy_Device_DeviceResponse, Error>) in
            lock.lock()
            pendingRequests[requestID] = cont
            lock.unlock()

            Task {
                do {
                    try await stream.requestStream.send(req)
                } catch {
                    lock.lock()
                    pendingRequests.removeValue(forKey: requestID)
                    lock.unlock()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Disconnect from relay
    public func disconnect() async {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        await performDisconnect()
    }

    /// Quick disconnect for wake-up reconnect; prioritizes speed over graceful shutdown.
    public func disconnectForReconnect() async {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        await performDisconnect()
    }

    private func performDisconnect() async {
        lock.lock()
        for (_, cont) in pendingRequests {
            cont.resume(throwing: NoxyError.general("Disconnected"))
        }
        pendingRequests.removeAll()
        lock.unlock()

        responseTask?.cancel()
        streamCall?.requestStream.finish()
        streamCall = nil
        let ch = channel
        channel = nil
        setSessionId(nil)
        setNetworkDeviceId(nil)
        decisionHandler = nil

        try? ch?.close().wait()
        try? eventLoopGroup?.syncShutdownGracefully()
        eventLoopGroup = nil
    }

    /// Authenticate device with relay.
    /// Returns true if the relay requires registration (device unknown to relay).
    public func authenticateDevice(_ device: NoxyDevice) async throws -> Bool {
        var req = Noxy_Device_DeviceRequest()
        req.payload = .authenticate(Noxy_Device_Authenticate.with { auth in
            auth.devicePubkeys = Noxy_Device_DevicePublicKeys.with { pk in
                pk.publicKey = device.publicKey
                pk.pqPublicKey = device.pqPublicKey
            }
        })

        let resp = try await sendAndWait(req)
        guard case .authenticate(let auth) = resp.payload else {
            if case .error(let e) = resp.payload {
                throw NoxyError.general("Authenticate failed: \(e.message)")
            }
            throw NoxyError.general("Unexpected authenticate response")
        }

        if auth.requiresRegistration {
            return true
        }
        if auth.hasDeviceID { setNetworkDeviceId(auth.deviceID) }
        if auth.hasSessionID { setSessionId(auth.sessionID) }
        return false
    }

    /// Announce (register) device with relay
    public func announceDevice(
        devicePubkeys: (publicKey: Data, pqPublicKey: Data),
        walletAddress: WalletAddress,
        signature: Data,
        apnToken: String? = nil
    ) async throws {
        var req = Noxy_Device_DeviceRequest()
        req.payload = .registerDevice(Noxy_Device_RegisterDevice.with { reg in
            reg.devicePubkeys = Noxy_Device_DevicePublicKeys.with { pk in
                pk.publicKey = devicePubkeys.publicKey
                pk.pqPublicKey = devicePubkeys.pqPublicKey
            }
            reg.walletAddress = walletAddress
            reg.signature = signature
            reg.type = "ios"
            if let tok = apnToken, !tok.isEmpty {
                reg.apnToken = tok
            }
        })

        let resp = try await sendAndWait(req)
        guard case .registerDevice(let reg) = resp.payload else {
            if case .error(let e) = resp.payload {
                throw NoxyError.general("Register failed: \(e.message)")
            }
            throw NoxyError.general("Unexpected register response")
        }

        setNetworkDeviceId(reg.deviceID)
        setSessionId(reg.sessionID)
    }

    /// Revoke device on relay
    public func revokeDevice(walletAddress: WalletAddress, signature: Data) async throws {
        var req = Noxy_Device_DeviceRequest()
        req.payload = .revokeDevice(Noxy_Device_RevokeDevice.with { rev in
            rev.walletAddress = walletAddress
            rev.signature = signature
        })
        _ = try await sendAndWait(req)
    }

    /// Rotate device keys on relay
    public func rotateDeviceKeys(
        newPubkeys: (publicKey: Data, pqPublicKey: Data),
        walletAddress: WalletAddress,
        signature: Data
    ) async throws {
        var req = Noxy_Device_DeviceRequest()
        req.payload = .rotateDeviceKeys(Noxy_Device_RotateDeviceKeys.with { rot in
            rot.newPubkeys = Noxy_Device_DevicePublicKeys.with { pk in
                pk.publicKey = newPubkeys.publicKey
                pk.pqPublicKey = newPubkeys.pqPublicKey
            }
            rot.walletAddress = walletAddress
            rot.signature = signature
        })
        _ = try await sendAndWait(req)
    }

    /// Subscribe to encrypted decision requests from the relay.
    /// - Parameter handler: Receives each event and optional relay `message_id` from the response (useful for delivery ack).
    public func subscribeToDecisions(
        handler: @escaping (NoxyEncryptedDecision, String?) async -> Void,
        apnToken: String? = nil
    ) async throws {
        decisionHandler = handler

        var req = Noxy_Device_DeviceRequest()
        req.payload = .subscribeDecisions(Noxy_Device_SubscribeDecisions.with { sub in
            sub.subscribe = true
            if let tok = apnToken, !tok.isEmpty { sub.apnToken = tok }
        })
        if let deviceId = currentDeviceId { req.deviceID = deviceId }
        if let sessionId = currentSessionId { req.sessionID = sessionId }

        _ = try await sendAndWait(req)
    }

    /// Sends ``DecisionOutcome`` (proto): user's **Approve** or **Reject** after they act in the UI.
    public func sendDecisionOutcome(
        decisionId: String,
        outcome: NoxyDecisionChoice,
        receivedAt: UInt64? = nil
    ) async throws {
        var req = Noxy_Device_DeviceRequest()
        let protoOutcome: Noxy_Device_DecisionOutcomeValue = outcome == .approve ? .approve : .reject
        req.payload = .decisionOutcome(Noxy_Device_DecisionOutcome.with { d in
            d.decisionID = decisionId
            d.outcome = protoOutcome
            d.receivedAt = receivedAt ?? UInt64(Date().timeIntervalSince1970 * 1000)
        })
        if let deviceId = currentDeviceId { req.deviceID = deviceId }
        if let sessionId = currentSessionId { req.sessionID = sessionId }
        _ = try await sendAndWait(req)
    }

    /// Sends ``DecisionAck`` (proto): relay is notified the device **received** the decision request (decrypt ok).
    /// For the user's Approve/Reject use ``sendDecisionOutcome(decisionId:outcome:receivedAt:)``.
    public func sendDecisionAck(decisionId: String, receivedAt: UInt64? = nil) async throws {
        var req = Noxy_Device_DeviceRequest()
        req.payload = .decisionAck(Noxy_Device_DecisionAck.with { a in
            a.decisionID = decisionId
            a.receivedAt = receivedAt ?? UInt64(Date().timeIntervalSince1970 * 1000)
        })
        if let deviceId = currentDeviceId { req.deviceID = deviceId }
        if let sessionId = currentSessionId { req.sessionID = sessionId }
        _ = try await sendAndWait(req)
    }
}

/// User-visible approve/reject for ``NoxyNetworkModule/sendDecisionOutcome(decisionId:outcome:receivedAt:)``.
public enum NoxyDecisionChoice: Sendable {
    case approve
    case reject
}

/// Encrypted decision event from the relay. Ciphertext = encrypted_data || tag (last 16 bytes are GCM auth tag).
public struct NoxyEncryptedDecision {
    public let kyberCt: Data
    public let nonce: Data
    public let ciphertext: Data

    public init(kyberCt: Data, nonce: Data, ciphertext: Data) {
        self.kyberCt = kyberCt
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Parse from relay payload (supports kyber_ct/kyberCt, base64 or raw)
    public init?(from dict: [String: Any]) {
        func toData(_ v: Any?, name: String) -> Data? {
            guard let v = v else { return nil }
            if let d = v as? Data { return d }
            if let arr = v as? [UInt8] { return Data(arr) }
            if let s = v as? String, let d = Data(base64Encoded: s) { return d }
            return nil
        }
        let kyberRaw = dict["kyber_ct"] ?? dict["kyberCt"]
        let nonceRaw = dict["nonce"]
        let ctRaw = dict["ciphertext"]
        guard let kyberCt = toData(kyberRaw, name: "kyber_ct"),
              let nonce = toData(nonceRaw, name: "nonce"),
              let ciphertext = toData(ctRaw, name: "ciphertext"),
              ciphertext.count >= 16 else { return nil }
        self.kyberCt = kyberCt
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Split ciphertext into encrypted part and tag (last 16 bytes)
    public var ciphertextWithoutTag: Data {
        ciphertext.prefix(ciphertext.count - 16)
    }

    public var tag: Data {
        ciphertext.suffix(16)
    }
}

/// Deprecated alias for ``NoxyEncryptedDecision``.
@available(*, deprecated, renamed: "NoxyEncryptedDecision")
public typealias NoxyEncryptedNotification = NoxyEncryptedDecision
