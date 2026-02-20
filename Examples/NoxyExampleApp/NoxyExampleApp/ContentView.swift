import SwiftUI
import NoxySDK

struct ContentView: View {
    @StateObject private var manager = NoxyClientManager()
    @State private var relayUrl = "https://localhost:4433"
    @State private var appId = "app_noxydev"
    @State private var errorMessage: String?
    @State private var isSubscribing = false
    @State private var isConnecting = false

    var body: some View {
        NavigationView {
            Form {
                Section("Network") {
                    TextField("Relay URL", text: $relayUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("App ID", text: $appId)
                        .textInputAutocapitalization(.never)
                }

                if let address = manager.walletAddress {
                    Section("Wallet") {
                        HStack {
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                UIPasteboard.general.string = address
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Status") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(manager.status)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Connected")
                        Spacer()
                        Image(systemName: manager.isConnected ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(manager.isConnected ? .green : .gray)
                    }
                    HStack {
                        Text("Subscribed")
                        Spacer()
                        Image(systemName: manager.isSubscribed ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(manager.isSubscribed ? .green : .gray)
                    }
                }

                Section("Actions") {
                    if !manager.isConnected {
                        Button {
                            Task { await connectOnAppear() }
                        } label: {
                            HStack {
                                if isConnecting {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text(isConnecting ? "Connecting..." : "Connect")
                            }
                        }
                        .disabled(isConnecting)
                    }

                    Button {
                        Task { await subscribe() }
                    } label: {
                        HStack {
                            if isSubscribing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSubscribing ? "Subscribing..." : "Subscribe for Notifications")
                        }
                    }
                    .disabled(isSubscribing || !manager.isConnected)

                    if manager.isConnected {
                        Button("Disconnect", role: .destructive) {
                            Task { await manager.disconnect() }
                        }
                    }
                }

                if let last = manager.lastNotification {
                    Section("Last Notification") {
                        ForEach(Array(last.keys.sorted()), id: \.self) { key in
                            if let value = last[key] {
                                HStack {
                                    Text(key)
                                    Spacer()
                                    Text(String(describing: value))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Noxy Example")
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
            .task {
                if !manager.isConnected {
                    await connectOnAppear()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func connectOnAppear() async {
        isConnecting = true
        errorMessage = nil
        do {
            let granted = try await manager.requestNotificationPermission()
            if !granted {
                errorMessage = "Notification permission denied"
                isConnecting = false
                return
            }

            let identity = DemoWallet.makeDemoIdentity()
            let network = NoxyNetworkOptions(
                appId: appId,
                relayUrl: relayUrl,
                insecureSkipTLSVerification: true
            )
            // Use .whenUnlockedThisDeviceOnly so Keychain persists on Simulator.
            // kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly does not work on Simulator
            // (no passcode/Secure Enclave). Use .whenPasscodeSetThisDeviceOnly on real devices.
            let storage = NoxyStorage(
                serviceName: "network.noxy.example",
                accessibility: .whenUnlockedThisDeviceOnly
            )

            try await manager.initialize(
                identity: identity,
                network: network,
                storage: storage
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }

    private func subscribe() async {
        isSubscribing = true
        errorMessage = nil

        do {
            try await manager.subscribe()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubscribing = false
    }
}

#Preview {
    ContentView()
}
