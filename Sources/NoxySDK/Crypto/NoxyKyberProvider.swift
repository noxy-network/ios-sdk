import Foundation
import CPQClean

/// Post-quantum keypair provider (ML-KEM-768 / Kyber768). PK=1184, SK=2400, CT=1088 bytes.
public struct NoxyKyberProvider {
    public init() {}

    /// Generate a post-quantum keypair (ML-KEM-768)
    public func keypair() -> (publicKey: Data, secretKey: Data) {
        var pk = [UInt8](repeating: 0, count: Int(NOXY_KYBER_PK_BYTES))
        var sk = [UInt8](repeating: 0, count: Int(NOXY_KYBER_SK_BYTES))
        noxy_kyber_keypair(&pk, &sk)
        return (Data(pk), Data(sk))
    }

    /// Decapsulate: recover shared secret from ciphertext using secret key
    public func decapsulate(secretKey: Data, ciphertext: Data) throws -> Data {
        guard secretKey.count == NOXY_KYBER_SK_BYTES, ciphertext.count == NOXY_KYBER_CT_BYTES else {
            throw NoxyError.general("Invalid Kyber key/ciphertext size")
        }
        var ss = [UInt8](repeating: 0, count: Int(NOXY_KYBER_SS_BYTES))
        secretKey.withUnsafeBytes { skPtr in
            ciphertext.withUnsafeBytes { ctPtr in
                _ = noxy_kyber_decapsulate(&ss, ctPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), skPtr.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }
        }
        return Data(ss)
    }

    /// Encapsulate: generate ciphertext and shared secret from public key (for testing)
    internal func encapsulate(publicKey: Data) throws -> (ciphertext: Data, sharedSecret: Data) {
        guard publicKey.count == NOXY_KYBER_PK_BYTES else {
            throw NoxyError.general("Invalid Kyber public key size")
        }
        var ct = [UInt8](repeating: 0, count: Int(NOXY_KYBER_CT_BYTES))
        var ss = [UInt8](repeating: 0, count: Int(NOXY_KYBER_SS_BYTES))
        var pk = [UInt8](publicKey)
        let ret = noxy_kyber_encapsulate(&ct, &ss, &pk)
        guard ret == 0 else {
            throw NoxyError.general("Kyber encapsulation failed: \(ret)")
        }
        return (Data(ct), Data(ss))
    }
}
