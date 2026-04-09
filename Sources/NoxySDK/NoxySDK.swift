import Foundation

/// Create a Noxy client for the Decision Layer (encrypted decision requests + outcomes).
///
/// - Parameters:
///   - identity: EOA or SCW wallet identity with signer
///   - network: Relay gRPC URL and app ID
/// - Returns: `NoxyClient`
///
/// Example:
/// ```swift
/// let identity = NoxyIdentity.eoa(NoxyEoaWalletIdentity(
///     address: "0x...",
///     signer: { data in try await wallet.signMessage(data) }
/// ))
/// let client = NoxyClient(
///     identity: identity,
///     network: NoxyNetworkOptions(appId: "your-app", relayUrl: "https://relay.noxy.network")
/// )
/// try await client.initialize()
/// try await client.on { messageId, decision in print(messageId as Any, decision) }
/// ```
public func createNoxyClient(
    identity: NoxyIdentity,
    network: NoxyNetworkOptions,
    storage: NoxyStorage = NoxyStorage()
) -> NoxyClient {
    NoxyClient(identity: identity, network: network, storage: storage)
}
