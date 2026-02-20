# Noxy iOS SDK

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

## Requirements

- iOS 15+ / macOS 12+
- Swift 5.9+

---

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/noxy-network/ios-sdk.git", from: "1.0.0"),
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

---

## Quick Start

```swift
import NoxySDK

// 1. Create identity with wallet signer
let identity = NoxyIdentity.eoa(NoxyEoaWalletIdentity(
    address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",
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
