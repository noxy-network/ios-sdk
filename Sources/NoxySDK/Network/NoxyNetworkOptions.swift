import Foundation

/// Network configuration for relay connection
public struct NoxyNetworkOptions {
    /// Dashboard **APP_ID**
    public let appId: String
    /// gRPC endpoint (e.g. "https://relay.noxy.network")
    public let relayUrl: String
    /// Dashboard **APP_SIGNING_SECRET** (device registration HMAC). Persisted server-side as `app_device_signing_secret`.
    public let appSigningSecret: String
    public let maxRetries: Int
    public let retryTimeoutMs: UInt64
    /// Optional APNs token (hex string). When provided, app works online and offline (wake-up pushes). When omitted, online only.
    public let apnToken: String?

    public init(
        appId: String,
        relayUrl: String,
        appSigningSecret: String,
        maxRetries: Int = 5,
        retryTimeoutMs: UInt64 = 15_000,
        apnToken: String? = nil
    ) {
        self.appId = appId
        self.relayUrl = relayUrl
        self.appSigningSecret = appSigningSecret
        self.maxRetries = maxRetries
        self.retryTimeoutMs = retryTimeoutMs
        self.apnToken = apnToken
    }
}
