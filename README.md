# 📦 @noxy-network/ios-sdk

IOS SDK for [Noxy](https://noxy.network).

## What is Noxy?

[Noxy](https://noxy.network) adds **human-in-the-loop** guardrails: encrypted prompts reach your app, the **user makes a decision**, and your app **sends the outcome** to the relay.

Users register a device once using **`appSigningSecret`** (registration HMAC). This SDK decrypts payloads locally and sends **`DecisionOutcome`** over **gRPC**.

## Before you integrate

Create your app at [noxy.network](https://noxy.network). On the dashboard, copy **APP_ID** into **`appId`** and **APP_SIGNING_SECRET** into **`appSigningSecret`** in `NoxyNetworkOptions`. Device registration uses an HMAC from **APP_SIGNING_SECRET**. Agent backends use a separate **app token**, not these values.

---

## Features

- **Human-in-the-loop payloads** — Kyber (post-quantum) + AES-GCM for encrypted prompts from the relay.
- **Relay identities** — **`wallet`**, **`email`**, **`phone`**, **`user_id`** — see [Relay identity types](#relay-identity-types) (Swift **`NoxyIdentity.userId`** ↔ wire **`user_id`**).
- **Subscribe / outcomes** — `SubscribeDecisions` on the relay; `sendDecisionOutcome` to publish the user’s outcome.
- **Optional APNs wake-up** — Reconnect when the app is backgrounded (`setApnsToken`, `handleWakeUpNotification`).
- **Secure storage** — iOS Keychain for device data and private keys.

---

## Relay identity types

The relay **`identity_type`** values are **`wallet`**, **`email`**, **`phone`**, and **`user_id`**. In Swift, **`NoxyIdentity.userId`** maps to relay **`user_id`**. Use **`logicalIdentityIdOf(_:)`** and **`NoxyClient.logicalIdentityId`** for the stable logical id string; **`address`** is defined only for wallet identities (**`eoa`** / **`scw`**).

Wallet flows use **`NoxyIdentity.eoa`** / **`scw`**. Non-wallet flows use **`NoxyIdentity.email`**, **`.phone`**, **`.userId`** (no separate registration signer). **`NoxyNetworkOptions.appSigningSecret`** supplies the registration HMAC for every kind.

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
| `identity` | **Yes** | `NoxyIdentity` | `.eoa` / `.scw` (**wallet**, include `signer`), or `.email`, `.phone`, `.userId` without a registration signer. |
| `network` | **Yes** | `NoxyNetworkOptions` | Relay URL, **`appId`**, and **`appSigningSecret`** (registration HMAC). |
| `storage` | No | `NoxyStorage` | Custom secure storage. Default: Keychain. |

---

### NoxyNetworkOptions

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `appId` | **Yes** | `String` | — | Application identifier from Noxy. |
| `relayUrl` | **Yes** | `String` | — | gRPC endpoint (e.g. `"https://relay.noxy.network"`). |
| `appSigningSecret` | **Yes** | `String` | — | Dashboard **APP_SIGNING_SECRET**; required for device registration (HMAC). |
| `maxRetries` | No | `Int` | `5` | Max retries for transient failures. |
| `retryTimeoutMs` | No | `UInt64` | `15_000` | Retry timeout in milliseconds. |
| `apnToken` | No | `String?` | `nil` | APNs token for wake-up pushes. When set, app works **online + offline**; when nil, **online only**. |

Delivery acknowledgements (`DecisionAck`) are sent automatically after each successfully decrypted decision when a decision id is available (`decision_id` / `decisionId` / `message_id` in the JSON, or the relay response `message_id`).

---

### NoxyIdentity (wallet, email, phone, user_id)

**NoxyEoaWalletIdentity** / **NoxyScwWalletIdentity** (relay **`identity_type`**: **`wallet`**):

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `address` | **Yes** | `WalletAddress` | — | EVM-style address (e.g. `0x742d35Cc...`). |
| `signer` | **Yes** | `(Data) async throws -> Signature` | — | Closure that signs data and returns `Signature(bytes:)`. |
| `chainId` | No | `String?` | `nil` | Chain ID for context. |
| `publicKey` | No | `Data?` | `nil` | Public key (if available). |
| `publicKeyType` | No | `NoxyIdentityCryptoKeyType?` | `nil` | Key type (e.g. `secp256k1`). |

Non-wallet identities do not use a separate registration signer; relay **`identity_type`** is **`email`**, **`phone`**, or **`user_id`** respectively:

```swift
NoxyIdentity.email(email: "you@example.com")
NoxyIdentity.phone(phone: "+15551234567")
NoxyIdentity.userId(userId: "internal-123")  // relay identity_type "user_id"
```

Helpers `logicalIdentityIdOf(_:)` and `relayIdentityTypeOf(_:)` align with the relay. On `NoxyClient`, use **`logicalIdentityId`** for the stable string across all kinds; **`address`** is wallet-only (fatal error for email/phone/user id).

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
| `sendDecisionOutcome(decisionId:outcome:receivedAt:)` | Send **`DecisionOutcome`** for the user’s choice |
| `sendDecisionAck(decisionId:receivedAt:)` | Delivery ack (not the user’s decision) |
| `handleWakeUpNotification(fetchCompletionHandler:)` | Reconnect decision stream when woken by APNs |
| `revokeDevice()` | Revoke device locally and on relay |
| `rotateKeys()` | Rotate device keys locally and on relay |
| `close()` | Disconnect from relay |

**Properties:** `logicalIdentityId`, `address` (wallet-only), `isDeviceActive`, `isRelayConnected`, `isNetworkReady`

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
    .package(url: "https://github.com/noxy-network/ios-sdk.git", from: "2.0.1"),
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

### Wallet (`identity_type` **wallet**)

```swift
import NoxySDK

let identity = NoxyIdentity.eoa(NoxyEoaWalletIdentity(
    address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    signer: { data in
        let sig = try await wallet.signMessage(data)
        return Signature(bytes: sig)
    }
))

let client = createNoxyClient(
    identity: identity,
    network: NoxyNetworkOptions(
        appId: "your-app-id",
        relayUrl: "https://relay.noxy.network",
        appSigningSecret: "paste-app-signing-secret-here",
    )
)

try await client.initialize()

try await client.on { messageId, decision in
    // Present UI — user decides; send outcome when ready
}

// Choose the `DecisionOutcome` case that matches the user’s selection (`.approve`, `.reject`, etc.).
try await client.sendDecisionOutcome(decisionId: "...", outcome: .approve)

await client.close()
```

### Email, phone, or `user_id`

```swift
// Relay identity_type "email"
let identity = NoxyIdentity.email(email: "you@example.com") { data in
    Signature(bytes: try await yourSigner.signDeviceBinding(data))
}

// Relay identity_type "phone"
// let identity = NoxyIdentity.phone(phone: "+15551234567") { ... }

// Relay identity_type "user_id" (Swift API: userId)
// let identity = NoxyIdentity.userId(userId: "internal-user-123") { ... }

let client = createNoxyClient(
    identity: identity,
    network: NoxyNetworkOptions(
        appId: "your-app-id",
        relayUrl: "https://relay.noxy.network",
        appSigningSecret: "paste-app-signing-secret-here",
    )
)
try await client.initialize()
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

### Email / phone / user id (relay **`user_id`**)

```swift
let emailIdentity = NoxyIdentity.email(email: "you@example.com")
let phoneIdentity = NoxyIdentity.phone(phone: "+15551234567")
let userIdIdentity = NoxyIdentity.userId(userId: "corp-user-xyz")

let network = NoxyNetworkOptions(
    appId: "your-app-id",
    relayUrl: "https://relay.noxy.network",
    appSigningSecret: "paste-app-signing-secret-here",
)
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

### Actionable notifications (decision outcomes)

Register a `UNNotificationCategory` with actions whose handlers call **`sendDecisionOutcome`**. Example identifiers matching common outcome values:

```swift
import UserNotifications

let approved = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [.foreground])
let rejected = UNNotificationAction(identifier: "REJECT", title: "Reject", options: [.foreground])
let category = UNNotificationCategory(identifier: "DECISION", actions: [approved, rejected], intentIdentifiers: [], options: [])
UNUserNotificationCenter.current().setNotificationCategories([category])
```

Set `content.categoryIdentifier`, post from `on(handler:)` as needed, and in `userNotificationCenter(_:didReceive:withCompletionHandler:)` read `decision_id` from `userInfo` and call **`sendDecisionOutcome`**.

### Revoke or Rotate Device

```swift
// Revoke device (removes from relay and local storage)
try await client.revokeDevice()

// Rotate device keys (new keys, same identity)
try await client.rotateKeys()
```

---

## Security model

- **Device registration** — Device signs once with the identity signer; the signature binds the device to the relay identity (**wallet**, **email**, **phone**, or **user_id**).
- **Human-in-the-loop payloads** — Kyber KEM, HKDF, AES-GCM for encrypted prompts from the relay.
- **Relay** — Sees ciphertext on the wire; plaintext is handled only on-device after decryption.

---

## API overview

| Method | Description |
|--------|-------------|
| `initialize()` | Load or create device, connect to relay, authenticate |
| `on(handler:)` | Subscribe to decisions; handler receives `(messageId, decision)` |
| `sendDecisionOutcome(decisionId:outcome:)` | Send **`DecisionOutcome`** for the user’s choice |
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
