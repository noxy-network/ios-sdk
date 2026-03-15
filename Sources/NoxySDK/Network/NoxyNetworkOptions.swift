import Foundation

/// Network configuration for relay connection
public struct NoxyNetworkOptions {
    public let appId: String
    /// gRPC endpoint (e.g. "https://relay.noxy.network")
    public let relayUrl: String
    public let maxRetries: Int
    public let retryTimeoutMs: UInt64
    public let requireAck: Bool
    /// Optional APNs token (hex string). When provided, app works online and offline (wake-up pushes). When omitted, online only.
    public let apnToken: String?

    public init(
        appId: String,
        relayUrl: String,
        maxRetries: Int = 5,
        retryTimeoutMs: UInt64 = 15_000,
        requireAck: Bool = false,
        apnToken: String? = nil
    ) {
        self.appId = appId
        self.relayUrl = relayUrl
        self.maxRetries = maxRetries
        self.retryTimeoutMs = retryTimeoutMs
        self.requireAck = requireAck
        self.apnToken = apnToken
    }
}
