import Foundation

/// EVM-style wallet address (0x...)
public typealias WalletAddress = String

/// Supported identity types
public enum NoxyIdentityType: String, Codable {
    case eoa = "eoa"
    case scw = "scw"
}

/// Cryptographic key types for identity
public enum NoxyIdentityCryptoKeyType: String, Codable {
    case ed25519
    case ed448
    case sr25519
    case secp256k1
    case secp256k1Schnorr = "secp256k1-schnorr"
}

/// Signature result from wallet signer
public struct Signature {
    public let bytes: Data
    public init(bytes: Data) { self.bytes = bytes }
}

/// Signer closure: signs arbitrary data and returns signature bytes
public typealias SignerClosure = (Data) async throws -> Signature

/// EOA (Externally Owned Account) wallet identity
public struct NoxyEoaWalletIdentity {
    public let type: NoxyIdentityType = .eoa
    public let chainId: String?
    public let address: WalletAddress
    public let publicKey: Data?
    public let publicKeyType: NoxyIdentityCryptoKeyType?
    public let signer: SignerClosure

    public init(
        chainId: String? = nil,
        address: WalletAddress,
        publicKey: Data? = nil,
        publicKeyType: NoxyIdentityCryptoKeyType? = nil,
        signer: @escaping SignerClosure
    ) {
        self.chainId = chainId
        self.address = address
        self.publicKey = publicKey
        self.publicKeyType = publicKeyType
        self.signer = signer
    }
}

/// Smart Contract Wallet identity
public struct NoxyScwWalletIdentity {
    public let type: NoxyIdentityType = .scw
    public let chainId: String?
    public let address: WalletAddress
    public let publicKey: Data?
    public let publicKeyType: NoxyIdentityCryptoKeyType?
    public let signer: SignerClosure

    public init(
        chainId: String? = nil,
        address: WalletAddress,
        publicKey: Data? = nil,
        publicKeyType: NoxyIdentityCryptoKeyType? = nil,
        signer: @escaping SignerClosure
    ) {
        self.chainId = chainId
        self.address = address
        self.publicKey = publicKey
        self.publicKeyType = publicKeyType
        self.signer = signer
    }
}

/// Union of supported identity types
public enum NoxyIdentity {
    case eoa(NoxyEoaWalletIdentity)
    case scw(NoxyScwWalletIdentity)

    public var address: WalletAddress {
        switch self {
        case .eoa(let id): return id.address
        case .scw(let id): return id.address
        }
    }

    public var signer: SignerClosure {
        switch self {
        case .eoa(let id): return id.signer
        case .scw(let id): return id.signer
        }
    }

    public var type: NoxyIdentityType {
        switch self {
        case .eoa: return .eoa
        case .scw: return .scw
        }
    }
}
