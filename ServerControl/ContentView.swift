import SwiftUI

struct PendingCommand: Identifiable {
    enum Target { case process(Int), docker }
    let id = UUID()
    let name: String
    let target: Target
    let action: ServerAction
    var title: String { "\(action.title) \(name)?" }
    var detail: String {
        switch action {
        case .start: return "Start this service on your Ubuntu server. You will authorize with Face ID, Touch ID or your device passcode."
        case .restart: return "This will briefly interrupt the service. You will authorize with Face ID, Touch ID or your device passcode."
        case .stop: return "This service will stop running until started again. You will authorize with Face ID, Touch ID or your device passcode."
        }
    }
}

struct ContentView: View {
    @StateObject private var api = ServerAPI()
    @State private var pending: PendingCommand?
    @State private var selectedTab = ContentView.initialTab
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance.v2") private var appearance = AppAppearance.system.rawValue

    private static var initialTab: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-pm2") { return 1 }
        if arguments.contains("--preview-docker") { return 2 }
        if arguments.contains("--preview-settings") || arguments.contains("--preview-notifications") { return 4 }
        #endif
        return 0
    }

    private var colorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dark-preview") { return .dark }
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") { return .light }
        #endif
        return AppAppearance(rawValue: appearance)?.scheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView(api: api) }
                .tabItem { Label("Home", systemImage: "square.grid.2x2") }
                .tag(0)
            NavigationStack { ProcessesView(api: api, requestCommand: { pending = $0 }) }
                .tabItem { Label("PM2", systemImage: "terminal") }
                .tag(1)
            NavigationStack { ContainersView(api: api, requestCommand: { pending = $0 }) }
                .tabItem { Label("Docker", systemImage: "shippingbox") }
                .tag(2)
            NavigationStack { GeminiView() }
                .tabItem { Label("Gemini", systemImage: "sparkles") }
                .tag(3)
            NavigationStack { SettingsView(api: api) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(Brand.accent)
        .preferredColorScheme(colorScheme)
        .task { await api.loadDashboard() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !api.actionBusy { Task { await api.loadDashboard() } }
        }
        .confirmationDialog(pending?.title ?? "Confirm command",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible, presenting: pending) { command in
                Button(command.action.title, role: command.action == .stop ? .destructive : nil) {
                    Task {
                        switch command.target {
                        case .process(let id): await api.processAction(id: id, name: command.name, action: command.action)
                        case .docker: await api.dockerAction(name: command.name, action: command.action)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { command in Text(command.detail) }
        .alert("Command not completed",
               isPresented: Binding(get: { api.actionError != nil }, set: { if !$0 { api.actionError = nil } })) {
            Button("OK", role: .cancel) { api.actionError = nil }
        } message: { Text(api.actionError ?? "") }
        .overlay(alignment: .center) {
            if api.actionBusy {
                HStack(spacing: 12) {
                    ProgressView().tint(Brand.accent)
                    Text(api.actionProgress).font(.subheadline.weight(.medium))
                }
                .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
