import Foundation
import UserNotifications
import NoxySDK

/// Manages NoxyClient lifecycle and bridges decrypted notifications to local notifications.
@MainActor
public final class NoxyClientManager: ObservableObject {
    @Published public private(set) var status: String = "Idle"
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isSubscribed: Bool = false
    @Published public private(set) var walletAddress: String?
    @Published public private(set) var lastNotification: [String: Any]?

    private var client: NoxyClient?
    private let notificationCenter = UNUserNotificationCenter.current()

    public init() {}

    /// Initialize Noxy client and connect to relay
    public func initialize(
        identity: NoxyIdentity,
        network: NoxyNetworkOptions,
        storage: NoxyStorage = NoxyStorage()
    ) async throws {
        status = "Connecting..."
        walletAddress = identity.address
        let client = NoxyClient(identity: identity, network: network, storage: storage)
        self.client = client

        try await client.initialize()
        isConnected = client.isRelayConnected
        status = client.isNetworkReady ? "Ready" : "Connected (awaiting session)"
    }

    /// Subscribe to notifications. Decrypted payloads are shown as local notifications.
    public func subscribe() async throws {
        guard let client else {
            status = "Not initialized"
            throw NoxyError.general("Call initialize first")
        }

        status = "Subscribing..."
        try await client.on { [weak self] payload in
            Task { @MainActor in
                self?.handleDecryptedNotification(payload)
            }
        }
        isSubscribed = true
        status = "Subscribed — waiting for notifications"
    }

    /// Disconnect from relay
    public func disconnect() async {
        await client?.close()
        client = nil
        isConnected = false
        isSubscribed = false
        walletAddress = nil
        status = "Disconnected"
    }

    private func handleDecryptedNotification(_ payload: [String: Any]) {
        #if DEBUG
        print("[NoxyExample] 3. Handler received decrypted notification: \(payload)")
        #endif
        lastNotification = payload

        let title = (payload["title"] as? String) ?? "Noxy Notification"
        let body = (payload["body"] as? String) ?? (payload["message"] as? String) ?? "New notification"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let data = payload["data"] as? [String: Any] {
            content.userInfo = data
        } else {
            content.userInfo = payload
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.status = "Notification error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Request notification permission. Call before subscribe.
    public func requestNotificationPermission() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        return try await notificationCenter.requestAuthorization(options: options)
    }
}
