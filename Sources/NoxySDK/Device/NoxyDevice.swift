import Foundation

/// Device descriptor and public keys
public struct NoxyDevice {
    public let identityId: WalletAddress
    public let appId: String
    public var isRevoked: Bool
    public let issuedAt: UInt64
    public let publicKey: Data
    public let pqPublicKey: Data
    public var identitySignature: Data?

    public init(
        identityId: WalletAddress,
        appId: String,
        isRevoked: Bool,
        issuedAt: UInt64,
        publicKey: Data,
        pqPublicKey: Data,
        identitySignature: Data?
    ) {
        self.identityId = identityId
        self.appId = appId
        self.isRevoked = isRevoked
        self.issuedAt = issuedAt
        self.publicKey = publicKey
        self.pqPublicKey = pqPublicKey
        self.identitySignature = identitySignature
    }
}

/// Device private keys (kept in secure storage)
public struct NoxyDevicePrivateKeys {
    public let privateKey: Data
    public let pqPrivateKey: Data

    public init(privateKey: Data, pqPrivateKey: Data) {
        self.privateKey = privateKey
        self.pqPrivateKey = pqPrivateKey
    }
}
