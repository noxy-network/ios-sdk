import Foundation
import Security

/// Keychain-based secure storage for device data and private keys.
/// All data is stored in the iOS Keychain (not UserDefaults or file system).
/// Device private keys use the configured accessibility level for protection.
public final class NoxyStorage {
    private let serviceName: String
    private let accessGroup: String?
    private let accessibility: CFString

    /// - Parameters:
    ///   - serviceName: Keychain service identifier (e.g. `"network.noxy.sdk"`)
    ///   - accessGroup: Optional Keychain access group for app extensions
    ///   - accessibility: Keychain accessibility. Default `.whenPasscodeSetThisDeviceOnly` (recommended).
    ///     Use `.whenUnlockedThisDeviceOnly` for Simulator (passcode-based storage does not persist there).
    public init(
        serviceName: String = "network.noxy.sdk",
        accessGroup: String? = nil,
        accessibility: NoxyStorageAccessibility = .whenPasscodeSetThisDeviceOnly
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
        self.accessibility = accessibility.cfValue
    }

    public func save(key: String, data: Data) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NoxyStorageError.saveFailed(status)
        }
    }

    public func load(key: String) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NoxyStorageError.loadFailed(status)
        }
        return data
    }

    public func delete(key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        SecItemDelete(query as CFDictionary)
    }

    public func loadAll(prefix: String) throws -> [Data] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw NoxyStorageError.loadFailed(status)
        }

        return items
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) }
            .compactMap { try? load(key: $0) }
    }
}

/// Keychain accessibility options for stored data.
/// Device private keys should use `.whenPasscodeSetThisDeviceOnly` in production.
public enum NoxyStorageAccessibility {
    /// Data available when device is unlocked; not backed up; not migrated to other devices.
    /// Use for Simulator—passcode-based storage does not persist there.
    case whenUnlockedThisDeviceOnly
    /// Same as above, plus requires device passcode. Recommended for production.
    case whenPasscodeSetThisDeviceOnly

    var cfValue: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly: return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

public enum NoxyStorageError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
}
