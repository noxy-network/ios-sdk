# 📦 @noxy-network/ios-sdk

**Noxy** is a decentralized push notification network for Web3 apps. This SDK lets your iOS app receive secure, end-to-end encrypted notifications using **wallet-based identity** — no emails or phone numbers.

Users register a device once with a wallet signature. After that, they receive real-time or store-and-forward notifications — **without centralized user accounts**.

---

## Features

- **Wallet-based identity** — EOA and Smart Contract Wallets; no email or phone
- **End-to-end encrypted notifications** — Kyber (post-quantum) + AES-GCM
- **One-time device registration** — Sign with wallet; device keys and post-quantum keys generated and stored in Keychain
- **Relay-based delivery** — gRPC connection to relay; real-time or store-and-forward
- **Secure storage** — iOS Keychain for device data and private keys (never UserDefaults)

---

## API Reference

### Main Entry Point: `createNoxyClient`

```swift
func createNoxyClient(
    identity: NoxyIdentity,
    network: NoxyNetworkOptions,
    storage: NoxyStorage = NoxyStorage()
) -> NoxyClient
```

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `identity` | **Yes** | `NoxyIdentity` | EOA or SCW wallet identity with signer. |
| `network` | **Yes** | `NoxyNetworkOptions` | Relay URL and app configuration. |
| `storage` | No | `NoxyStorage` | Custom secure storage. Default: Keychain. |

---

### NoxyNetworkOptions

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `appId` | **Yes** | `String` | — | Application identifier from Noxy. |
| `relayUrl` | **Yes** | `String` | — | gRPC endpoint (e.g. `"https://relay.noxy.network"`). |
| `maxRetries` | No | `Int` | `5` | Max retries for transient failures. |
| `retryTimeoutMs` | No | `UInt64` | `15_000` | Retry timeout in milliseconds. |
| `requireAck` | No | `Bool` | `false` | Require acknowledgment for push delivery. |
| `apnToken` | No | `String?` | `nil` | APNs token for wake-up pushes. When set, app works **online + offline**; when nil, **online only**. |

---

### NoxyIdentity & Wallet Identity

**NoxyEoaWalletIdentity** / **NoxyScwWalletIdentity**:

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `address` | **Yes** | `WalletAddress` | — | EVM-style address (e.g. `0x742d35Cc...`). |
| `signer` | **Yes** | `(Data) async throws -> Signature` | — | Closure that signs data and returns `Signature(bytes:)`. |
| `chainId` | No | `String?` | `nil` | Chain ID for context. |
| `publicKey` | No | `Data?` | `nil` | Public key (if available). |
| `publicKeyType` | No | `NoxyIdentityCryptoKeyType?` | `nil` | Key type (e.g. `secp256k1`). |

---

### NoxyStorage

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `serviceName` | No | `String` | `"network.noxy.sdk"` | Keychain service identifier. |
| `accessGroup` | No | `String?` | `nil` | Keychain access group for app extensions. |
| `accessibility` | No | `NoxyStorageAccessibility` | `.whenPasscodeSetThisDeviceOnly` | Keychain accessibility. Use `.whenUnlockedThisDeviceOnly` for Simulator. |

---

### NoxyClient Methods

| Method | Description |
|--------|-------------|
| `initialize()` | Load or create device, connect to relay, authenticate |
| `setApnsToken(_:)` | Register APNs token for wake-up pushes when backgrounded |
| `on(handler:)` | Subscribe to notifications; handler receives `[String: Any]` |
| `handleWakeUpNotification(fetchCompletionHandler:)` | Reconnect and fetch when woken by APNs |
| `revokeDevice()` | Revoke device locally and on relay |
| `rotateKeys()` | Rotate device keys locally and on relay |
| `close()` | Disconnect from relay |

**Properties:** `address`, `isDeviceActive`, `isRelayConnected`, `isNetworkReady`

---

### NoxyError

| Case | When |
|------|------|
| `initializationFailed(String)` | Device creation or setup fails. |
| `general(String)` | Revoke, rotate, auth, or other operation fails. |

---

### Notification Payload

The handler receives a decrypted `[String: Any]` (JSON object). Common fields: `title`, `body`, `data`.

---

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/noxy-network/ios-sdk.git", from: "1.0.1"),
],
targets: [
    .target(name: "YourApp", dependencies: ["NoxySDK"]),
]
```

Or for local development:

```swift
dependencies: [
    .package(path: "../ios-sdk"),
],
```

### Build requirements

- **Xcode 15+** or **Swift 5.9+**
- **Remote install:** The repo must be tagged (e.g. `1.0.1`) for the URL to resolve.
- **Xcode app projects:** Add the package via **File → Add Package Dependencies**, then add `NoxySDK` to your target’s **Frameworks and Libraries**.

Once the package is resolved and linked, `import NoxySDK` will work.

---

## Quick Start

```swift
import NoxySDK

// 1. Create identity with wallet signer
let identity = NoxyIdentity.eoa(NoxyEoaWalletIdentity(
    address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    signer: { data in
        let sig = try await wallet.signMessage(data)
        return Signature(bytes: sig)
    }
))

// 2. Create client
let client = createNoxyClient(
    identity: identity,
    network: NoxyNetworkOptions(
        appId: "your-app-id",
        relayUrl: "https://relay.noxy.network"
    )
)

// 3. Initialize (loads or registers device, connects to relay)
try await client.initialize()

// 4. Subscribe to notifications
try await client.on { notification in
    print("Notification:", notification)
    // notification is the decrypted payload (e.g. { "title": "...", "body": "...", "data": {...} })
}

// 5. Disconnect when done
await client.close()
```

---

## Usage Examples

### EOA Identity (Externally Owned Account)

```swift
let identity = NoxyIdentity.eoa(NoxyEoaWalletIdentity(
    address: walletAddress,
    signer: { data in
        let sig = try await yourWallet.signMessage(data)
        return Signature(bytes: sig)
    }
))
```

### Smart Contract Wallet Identity

```swift
let identity = NoxyIdentity.scw(NoxyScwWalletIdentity(
    address: scwAddress,
    signer: { data in
        let sig = try await yourWallet.signMessage(data)
        return Signature(bytes: sig)
    }
))
```

### Custom Storage (Keychain)

```swift
let storage = NoxyStorage(
    serviceName: "com.yourapp.noxy",
    accessibility: .whenPasscodeSetThisDeviceOnly  // Recommended for production
)

// For Simulator (passcode-based storage does not persist):
let storage = NoxyStorage(
    serviceName: "com.yourapp.noxy",
    accessibility: .whenUnlockedThisDeviceOnly
)

let client = createNoxyClient(
    identity: identity,
    network: networkOptions,
    storage: storage
)
```

### Displaying Notifications

Request notification permission and show decrypted notifications as local alerts:

```swift
import UserNotifications

// Request permission before initialize
let granted = try await UNUserNotificationCenter.current()
    .requestAuthorization(options: [.alert, .sound, .badge])

if granted {
    try await client.initialize()
    try await client.on { payload in
        let content = UNMutableNotificationContent()
        content.title = payload["title"] as? String ?? "Notification"
        content.body = payload["body"] as? String ?? "New notification"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

### Revoke or Rotate Device

```swift
// Revoke device (removes from relay and local storage)
try await client.revokeDevice()

// Rotate device keys (new keys, same identity)
try await client.rotateKeys()
```

---

## Security Model

- **Device registration** — Device signs once with the wallet; the signature binds the device to the identity.
- **Notification encryption** — Kyber KEM for key agreement, HKDF for key derivation, AES-GCM for payload encryption.
- **Relay** — Sees only encrypted payloads; no plaintext and no need for centralized user accounts.

---

## API Overview

| Method | Description |
|--------|-------------|
| `initialize()` | Load or create device, connect to relay, authenticate |
| `on(handler:)` | Subscribe to notifications; handler receives decrypted payload |
| `revokeDevice()` | Revoke device locally and on relay |
| `rotateKeys()` | Rotate device keys locally and on relay |
| `close()` | Disconnect from relay |

---

## Proto & gRPC

The network layer uses gRPC with generated client from `proto/noxy.device.proto`. To regenerate after proto changes:

```bash
./scripts/generate.sh
```

Requires `protoc`, `protoc-gen-swift` (swift-protobuf), and `protoc-gen-grpc-swift` (grpc-swift).

---

## License

MIT © Noxy Network
