import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var api: ServerAPI
    @State private var serverURL = ""
    @State private var token = ""
    @State private var result = ""
    @State private var testing = false
    @State private var removeConfirmation = false
    @State private var notificationPreview = false
    @AppStorage("appearance.v2") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Server Control").font(.title3.bold())
                        Text("Your infrastructure, within reach.").font(.caption).foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.1.0")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }
            Section {
                TextField("HTTPS server URL", text: $serverURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Server URL")
                SecureField(api.hasSavedToken ? "Replace saved token (optional)" : "Server token", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Server token")
                LabeledContent("Active endpoint", value: api.activeBaseURL == ServerAPI.defaultBaseURL ? "Production" : "Tailscale fallback")
                LabeledContent("Token", value: api.hasSavedToken ? "Saved in Keychain" : "Not configured")
                    .font(.subheadline)
                Button("Save & connect") {
                    do {
                        try api.saveConnection(url: serverURL, replacementToken: token)
                        token = ""
                        result = "Saved securely. Connecting…"
                        Task {
                            await api.loadDashboard()
                            result = api.connection == .connected ? "Connected. Your dashboard is up to date." : (api.errorMessage ?? "Add a token to connect.")
                        }
                    } catch { result = api.friendly(error) }
                }.disabled(api.loading || api.actionBusy || testing)
                Button {
                    testing = true
                    Task {
                        defer { testing = false }
                        do {
                            let health = try await api.healthCheck()
                            result = health.ok ? "Saved server is reachable. This public health check does not verify your token." : "Saved server reports a health issue."
                        } catch { result = api.friendly(error) }
                    }
                } label: {
                    HStack {
                        Text("Test saved server")
                        if testing { Spacer(); ProgressView() }
                    }
                }.disabled(testing || api.loading || api.actionBusy)
                if !result.isEmpty { Text(result).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Server connection") }
              footer: { Text("The production HTTPS address is already configured. Tailscale VPN is not required on this iPhone. Leave the token field blank to keep your saved token.") }
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Protected server controls").font(.subheadline.bold())
                        Text("The app locks in the background. Every command needs confirmation and Face ID, Touch ID or your device passcode. Without a device passcode, commands remain locked.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "lock.shield").foregroundStyle(Brand.teal) }
                Button("Remove saved token", role: .destructive) { removeConfirmation = true }
                    .disabled(!api.hasSavedToken || api.loading || api.actionBusy || testing)
            } header: { Text("Security") }
              footer: { Text("Your bearer token stays in iOS Keychain, accessible only while the device is unlocked. Gemini, Meta and Discord credentials stay on Ubuntu.") }
            Section("Personalize") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                NavigationLink { NotificationSettingsView() } label: {
                    Label("Local notifications", systemImage: "bell.badge")
                }
            }
            Section {
                LabeledContent("Distribution", value: "SideStore")
                LabeledContent("Minimum iOS", value: "17")
                Text("Service status comes from your authenticated ServerControl backend.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("About") }
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            serverURL = api.baseURL
            #if DEBUG
            notificationPreview = ProcessInfo.processInfo.arguments.contains("--preview-notifications")
            #endif
        }
        .navigationDestination(isPresented: $notificationPreview) { NotificationSettingsView() }
        .onDisappear { token = "" }
        .confirmationDialog("Remove the saved token?", isPresented: $removeConfirmation, titleVisibility: .visible) {
            Button("Remove token", role: .destructive) {
                Task {
                    do {
                        try await DeviceAuthorization.authorize(reason: "Remove the saved Server Control token.")
                        try api.removeToken()
                        token = ""
                        result = "Token removed from this iPhone."
                    } catch {
                        result = DeviceAuthorization.isCancellation(error) ? "Cancelled. Token was kept." : api.friendly(error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This disconnects the app. It does not change or revoke the token on Ubuntu.") }
    }
}
