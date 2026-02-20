import Foundation

/// Network configuration for relay connection
public struct NoxyNetworkOptions {
    public let appId: String
    /// gRPC endpoint (e.g. "https://relay.noxy.network")
    public let relayUrl: String
    public let maxRetries: Int
    public let retryTimeoutMs: UInt64
    public let requireAck: Bool
    /// Skips TLS certificate verification. Use only in development; never enable in production.
    public let insecureSkipTLSVerification: Bool

    public init(
        appId: String,
        relayUrl: String,
        maxRetries: Int = 5,
        retryTimeoutMs: UInt64 = 15_000,
        requireAck: Bool = false,
        insecureSkipTLSVerification: Bool = false
    ) {
        self.appId = appId
        self.relayUrl = relayUrl
        self.maxRetries = maxRetries
        self.retryTimeoutMs = retryTimeoutMs
        self.requireAck = requireAck
        self.insecureSkipTLSVerification = insecureSkipTLSVerification
    }
}
