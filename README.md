# 📦 @noxy-network/ios-sdk

IOS SDK to integrate with the [Noxy](https://noxy.network) **Decision Layer**: subscribe to encrypted decision requests, present them to the user, and respond with decision — all with wallet-based identity.

Users register a device once with a wallet signature. The relay streams encrypted decision payloads; the SDK decrypts them locally and can send `DecisionOutcome` back over the same gRPC session.

**Before you integrate:** Create your app at [noxy.network](https://noxy.network). When the app is created, you receive an **app id** and an **app token** (auth token). This iOS SDK uses the **app id** (`appId` in `NoxyNetworkOptions`). The **app token** is for agent/orchestrator SDKs (Go, Rust, Python, Node, etc.), not for this package.

---

## Features

- **Wallet-based identity** — EOA and Smart Contract Wallets
- **Encrypted decision events** — Kyber (post-quantum) + AES-GCM for payloads from the Decision Layer
- **Subscribe / outcomes** — `SubscribeDecisions` on the relay; `sendDecisionOutcome` for approve/reject
- **Optional APNs wake-up** — Reconnect when the app is backgrounded (`setApnsToken`, `handleWakeUpNotification`)
- **Secure storage** — iOS Keychain for device data and private keys

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
| `apnToken` | No | `String?` | `nil` | APNs token for wake-up pushes. When set, app works **online + offline**; when nil, **online only**. |

Delivery acknowledgements (`DecisionAck`) are sent automatically after each successfully decrypted decision when a decision id is available (`decision_id` / `decisionId` / `message_id` in the JSON, or the relay response `message_id`).

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
| `setApnsToken(_:)` | Register APNs token for wake-up when backgrounded |
| `on(handler:)` | Subscribe to encrypted decisions; handler receives `(messageId, decision)` |
| `sendDecisionOutcome(decisionId:outcome:receivedAt:)` | Send approve/reject to the relay |
| `sendDecisionAck(decisionId:receivedAt:)` | Delivery ack (not the user’s decision) |
| `handleWakeUpNotification(fetchCompletionHandler:)` | Reconnect decision stream when woken by APNs |
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

### Decision payload

`on(handler:)` passes `messageId` (relay stream id, optional) and `decision` (decrypted `[String: Any]` JSON). Use `messageId` for `sendDecisionOutcome` when JSON has no `decision_id` / `decisionId`. Other fields (e.g. `title`, `body`) are app-specific.

---

### Wake-up and background

- **Works when:** App is suspended, backgrounded, or device is locked (network allowed for the remote-notification fetch, typically up to ~30 seconds).
- **Does not work when:** User has force-quit the app (iOS will not launch for pushes).
- **Requires:** `remote-notification` in `UIBackgroundModes` and `handleWakeUpNotification` from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.

---

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/noxy-network/ios-sdk.git", from: "2.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["NoxySDK"]),
]
```

### Build requirements

- **Xcode 15+** or **Swift 5.9+**
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

// 4. Subscribe to decision requests from the relay
try await client.on { messageId, decision in
    print("messageId:", messageId as Any, "decision:", decision)
    // Show UI, use UNMutableNotificationContent
    // e.g. decision_id, title, body — use sendDecisionOutcome when the user approves/rejects
}

// 5. after user taps Approve/Reject in your UI:
try await client.sendDecisionOutcome(decisionId: "...", outcome: .approve)

// 6. Disconnect when done
await client.close()
```

---

## Usage

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

### Actionable notifications (Approve / Reject)

Register a `UNNotificationCategory` with two `UNNotificationAction`s, set `content.categoryIdentifier`, and schedule a local notification from `on(handler:)`. In `userNotificationCenter(_:didReceive:withCompletionHandler:)`, read `decision_id` from `userInfo` and call `sendDecisionOutcome`.

```swift
import UserNotifications

let approved = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [.foreground])
let rejected = UNNotificationAction(identifier: "REJECT", title: "Reject", options: [.foreground])
let category = UNNotificationCategory(identifier: "DECISION", actions: [approved, rejected], intentIdentifiers: [], options: [])
UNUserNotificationCenter.current().setNotificationCategories([category])
```

### Revoke or Rotate Device

```swift
// Revoke device (removes from relay and local storage)
try await client.revokeDevice()

// Rotate device keys (new keys, same identity)
try await client.rotateKeys()
```

---

## Security model

- **Device registration** — Device signs once with the wallet; the signature binds the device to the identity.
- **Decision encryption** — Kyber KEM, HKDF, AES-GCM for decision payloads from the relay.
- **Relay** — Sees ciphertext on the wire; plaintext is handled only on-device after decryption.

---

## API overview

| Method | Description |
|--------|-------------|
| `initialize()` | Load or create device, connect to relay, authenticate |
| `on(handler:)` | Subscribe to decisions; handler receives `(messageId, decision)` |
| `sendDecisionOutcome(decisionId:outcome:)` | Send approve/reject |
| `revokeDevice()` | Revoke device locally and on relay |
| `rotateKeys()` | Rotate device keys locally and on relay |
| `close()` | Disconnect from relay |

---

## Example app

The only bundled sample is **`Examples/NoxyExampleApp/`**: open **`NoxyExampleApp.xcodeproj`** and follow **`Examples/NoxyExampleApp/README.md`**.

---

## Proto & code generation

The network layer uses gRPC with types from `proto/noxy.device.proto`. Regenerate **`noxy.device.pb.swift`** after proto changes:

```bash
./scripts/generate.sh
```

Requires `protoc` and `protoc-gen-swift` (e.g. `brew install swift-protobuf`). The `noxy.device.grpc.swift` stub is kept for **grpc-swift 1.x**; update it only if the RPC surface changes.

---

## License

MIT © Noxy Network
