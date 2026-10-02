import SwiftUI
import UserNotifications
import Combine

enum AlertCategory: String, Codable, CaseIterable, Identifiable {
    case server, pm2, docker, resources, gemini, classera, padel, tv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .server: return "Server availability"
        case .pm2: return "PM2 crashes"
        case .docker: return "Docker health"
        case .resources: return "CPU, memory & disk"
        case .gemini: return "Gemini key health"
        case .classera: return "Classera results"
        case .padel: return "Padel errors"
        case .tv: return "TV / ADB connectivity"
        }
    }
    var symbol: String {
        switch self {
        case .server: return "server.rack"
        case .pm2: return "terminal"
        case .docker: return "shippingbox"
        case .resources: return "gauge.with.dots.needle.67percent"
        case .gemini: return "sparkles"
        case .classera: return "graduationcap"
        case .padel: return "sportscourt"
        case .tv: return "tv"
        }
    }
}

struct AlertPreferences: Codable {
    var categories: Set<AlertCategory> = [.server, .pm2, .docker, .resources]
    var cpuThreshold = 85
    var memoryThreshold = 85
    var diskThreshold = 90
}

// The server will eventually emit these events through a separately provisioned transport.
// This app never receives Gemini, Meta or Discord credentials.
struct ServerAlertEvent: Codable, Identifiable {
    enum Severity: String, Codable { case information, warning, critical }
    let id: UUID
    let category: AlertCategory
    let severity: Severity
    let title: String
    let message: String
    let occurredAt: Date
}

protocol ServerAlertTransport {
    var isAvailable: Bool { get }
    var explanation: String { get }
}

struct DeferredAlertTransport: ServerAlertTransport {
    let isAvailable = false
    let explanation = "Server alerts are not connected yet. The current free Apple ID / SideStore build does not support the required APNs provisioning. A future server-side transport must deliver alerts while this app is closed."
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    let transport = DeferredAlertTransport()
    @Published var preferences: AlertPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "alerts.preferences.v2") }
        }
    }
    @Published private(set) var permission = "Not requested"
    @Published private(set) var permissionAllowed = false
    @Published private(set) var busy = false
    @Published var result: String?
    private let center = UNUserNotificationCenter.current()

    override init() {
        if let data = UserDefaults.standard.data(forKey: "alerts.preferences.v2"),
           let saved = try? JSONDecoder().decode(AlertPreferences.self, from: data) {
            preferences = saved
        } else { preferences = AlertPreferences() }
        super.init()
        center.delegate = self
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: permission = "Allowed"; permissionAllowed = true
        case .provisional: permission = "Quiet delivery"; permissionAllowed = true
        case .ephemeral: permission = "Temporary"; permissionAllowed = true
        case .denied: permission = "Disabled in iPhone Settings"; permissionAllowed = false
        case .notDetermined: permission = "Not requested"; permissionAllowed = false
        @unknown default: permission = "Unknown"; permissionAllowed = false
        }
    }

    func requestLocalPermission() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshPermission()
            result = permissionAllowed ? "Local notifications are allowed. Server alert delivery is still not connected." : "Notifications are disabled. You can change this in iPhone Settings."
        } catch { result = "Notification permission could not be requested. Try again in iPhone Settings." }
    }

    func sendLocalTest() async {
        busy = true
        defer { busy = false }
        await refreshPermission()
        guard permissionAllowed else { result = "Allow local notifications first. This does not enable remote server alerts."; return }
        let content = UNMutableNotificationContent()
        content.title = "Server Control"
        content.body = "Local notification test. Server monitoring is not connected yet."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "servercontrol-local-test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        do {
            try await center.add(request)
            result = "A local test will appear in 5 seconds. This is not a server alert."
        } catch { result = "The local test could not be scheduled." }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct NotificationSettingsView: View {
    @ObservedObject private var manager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ready for a future transport").font(.headline)
                        Text(manager.transport.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                } icon: { Image(systemName: "bell.badge").foregroundStyle(Brand.accent) }
                LabeledContent("Server delivery", value: "Not connected")
            } footer: {
                Text("V2 does not register with APNs, poll in the background, or promise alerts when closed.")
            }
            Section {
                ForEach(AlertCategory.allCases) { category in
                    Toggle(isOn: Binding(get: { manager.preferences.categories.contains(category) },
                                         set: { enabled in
                                             if enabled { manager.preferences.categories.insert(category) }
                                             else { manager.preferences.categories.remove(category) }
                                         })) {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            } header: { Text("Future alert preferences") }
              footer: { Text("Saved on this iPhone only. These preferences do not activate server monitoring yet.") }
            Section("Resource thresholds") {
                threshold("CPU", value: $manager.preferences.cpuThreshold)
                threshold("Memory", value: $manager.preferences.memoryThreshold)
                threshold("Disk", value: $manager.preferences.diskThreshold)
            }
            Section {
                LabeledContent("Permission", value: manager.permission)
                Button("Allow local notifications") { Task { await manager.requestLocalPermission() } }.disabled(manager.busy)
                Button("Send a local test") { Task { await manager.sendLocalTest() } }
                    .disabled(manager.busy || !manager.permissionAllowed)
                if let result = manager.result { Text(result).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Local notification test") }
              footer: { Text("A local test verifies iPhone permission and presentation. It is independent of the Ubuntu server.") }
        }
        .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
        .task { await manager.refreshPermission() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await manager.refreshPermission() } } }
    }

    private func threshold(_ title: String, value: Binding<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue)%", value: value, in: 50...100, step: 5)
            .monospacedDigit()
    }
}
