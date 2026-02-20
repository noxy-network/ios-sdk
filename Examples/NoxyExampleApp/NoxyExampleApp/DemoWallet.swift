import Foundation
import NoxySDK

/// Demo wallet for example app. Replace the signer with your Web3 wallet (WalletConnect, MetaMask, etc.)
/// For relay registration to succeed, the signer must produce a valid ECDSA secp256k1 signature.
public struct DemoWallet {
    public let address: String
    private let signer: SignerClosure

    public init(address: String, signer: @escaping SignerClosure) {
        self.address = address
        self.signer = signer
    }

    /// Creates a demo identity. Uses a mock signer that returns a placeholder signature.
    /// Replace with your wallet's signMessage to work with the relay.
    public static func makeDemoIdentity() -> NoxyIdentity {
        let address = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1"
        let signer: SignerClosure = { data in
            // TODO: Replace with your wallet's signMessage (e.g. WalletConnect, MetaMask SDK)
            // For demo: return a 65-byte placeholder. Relay will reject invalid signatures.
            // Example with WalletConnect: return Signature(bytes: try await wallet.signMessage(data))
            let placeholder = Data(repeating: 0, count: 65)
            return Signature(bytes: placeholder)
        }
        return .eoa(NoxyEoaWalletIdentity(
            address: address,
            signer: signer
        ))
    }
}
