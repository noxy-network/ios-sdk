import Foundation

/// EVM-style wallet address (0x...)
public typealias WalletAddress = String

/// Relay-facing identity category (`wallet`, `email`, `phone`, `user_id`).
public enum NoxyRelayIdentityType: String, Codable {
    case wallet
    case email
    case phone
    case userId = "user_id"
}

/// Wallet implementation kind (EOA vs SCW). Only meaningful for [NoxyRelayIdentityType.wallet].
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

/// Union of supported identities for the relay (wallet plus logical ids).
public enum NoxyIdentity {
    case eoa(NoxyEoaWalletIdentity)
    case scw(NoxyScwWalletIdentity)
    case email(email: String)
    case phone(phone: String)
    case userId(userId: String)

    /// Wallet address when identity is EOA or SCW.
    public var walletAddress: WalletAddress {
        switch self {
        case .eoa(let id): return id.address
        case .scw(let id): return id.address
        case .email, .phone, .userId:
            fatalError("walletAddress is only available for eoa or scw identity")
        }
    }

    /// Legacy alias for [walletAddress] on wallet identities.
    public var address: WalletAddress { walletAddress }

    /// EOA vs SCW when this is a wallet identity; otherwise `nil`.
    public var walletKind: NoxyIdentityType? {
        switch self {
        case .eoa(let id): return id.type
        case .scw(let id): return id.type
        case .email, .phone, .userId: return nil
        }
    }
}

public func relayIdentityTypeOf(_ identity: NoxyIdentity) -> NoxyRelayIdentityType {
    switch identity {
    case .eoa, .scw: return .wallet
    case .email: return .email
    case .phone: return .phone
    case .userId: return .userId
    }
}

public func logicalIdentityIdOf(_ identity: NoxyIdentity) -> String {
    switch identity {
    case .eoa(let id): return id.address
    case .scw(let id): return id.address
    case .email(let email): return email
    case .phone(let phone): return phone
    case .userId(let userId): return userId
    }
}

extension NoxyRelayIdentityType {
    var proto: Noxy_Device_IdentityType {
        switch self {
        case .wallet: return .wallet
        case .email: return .email
        case .phone: return .phone
        case .userId: return .userID
        }
    }
}
