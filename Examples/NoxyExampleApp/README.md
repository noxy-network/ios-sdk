# Noxy Example App

A minimal iOS app demonstrating Noxy SDK usage: initialize client with web3 wallet, subscribe for notifications, receive and decrypt encrypted push events, and render them as local notifications.

## Storage (Keychain)

`NoxyStorage` uses **iOS Keychain** for all device data and private keys—never UserDefaults or the file system. By default it uses `.whenPasscodeSetThisDeviceOnly`, so keys are protected by the device passcode and are not backed up or migrated.

## Flow

1. **Auto-connect** — On app start, connects to relay and authenticates/registers device
2. **Subscribe** — Tap "Subscribe for Notifications" to subscribe to the push stream
3. **Receive** — Relay sends encrypted notification (Kyber + AES-GCM)
4. **Decrypt** — SDK decapsulates Kyber ciphertext, derives AES key, decrypts payload
5. **Render** — Handler receives `[String: Any]` and triggers `UNUserNotificationCenter` to show a local notification

## Setup

1. Open `NoxyExampleApp.xcodeproj` in Xcode
2. Select your device or simulator
3. Build and run

## Configuration

- **Relay URL**: Default `https://localhost:4433` for local dev. Use `https://relay.noxy.network` for production.
- **App ID**: Default `app_noxydev`. Must match your app ID.
- **TLS**: The example uses `insecureSkipTLSVerification: true` for local development with self-signed certs (fixes "UnknownCA" errors). Never enable this in production.

## Wallet Integration

The example uses `DemoWallet.makeDemoIdentity()` with a **mock signer** that returns a placeholder signature. The relay will reject registration with an invalid signature.

To work with a real relay:

1. Replace the signer in `DemoWallet.swift` with your Web3 wallet's `signMessage`:
   - [WalletConnect Swift](https://github.com/WalletConnect/WalletConnectSwiftV2)
   - [MetaMask SDK](https://github.com/MetaMask/metamask-ios-sdk)
   - Or any wallet that can sign arbitrary data (ECDSA secp256k1)

2. Example with WalletConnect:
   ```swift
   let signer: SignerClosure = { data in
       let signature = try await wallet.signMessage(data)
       return Signature(bytes: signature)
   }
   ```

## Sending Test Notifications

Use your relay to send an encrypted push to the device. The relay encrypts with the device's ML-KEM public key. The SDK decrypts using the stored secret key and displays the payload as a local notification.

Expected payload shape (from relay):
```json
{
  "title": "Hello",
  "body": "You have a new message",
  "message": "Optional fallback",
  "data": { ... }
}
```

The app shows `title` and `body`/`message` in the notification. Extra fields appear in the "Last Notification" section.
