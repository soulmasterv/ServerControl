import SwiftUI

struct ContentView: View {

    @StateObject private var api = ServerAPI()

    var body: some View {

        TabView {

            NavigationStack {
                HomeView(api: api)
            }
            .tabItem {
                Label(
                    "Home",
                    systemImage: "server.rack"
                )
            }

            NavigationStack {
                PM2View(api: api)
            }
            .tabItem {
                Label(
                    "PM2",
                    systemImage: "terminal"
                )
            }

            NavigationStack {
                DockerView(api: api)
            }
            .tabItem {
                Label(
                    "Docker",
                    systemImage: "shippingbox"
                )
            }

            NavigationStack {
                GeminiView()
            }
            .tabItem {
                Label(
                    "Gemini",
                    systemImage: "sparkles"
                )
            }

            NavigationStack {
                SettingsView(api: api)
            }
            .tabItem {
                Label(
                    "Settings",
                    systemImage: "gear"
                )
            }
        }
        .task {
            await api.loadDashboard()
        }
    }
}

struct HomeView: View {

    @ObservedObject var api: ServerAPI

    var body: some View {

        ScrollView {

            VStack(spacing: 16) {

                if let server = api.dashboard?.server {

                    HStack {

                        Circle()
                            .fill(.green)
                            .frame(
                                width: 10,
                                height: 10
                            )

                        Text("Server Online")
                            .font(.headline)

                        Spacer()
                    }

                    statCard(
                        "CPU",
                        String(format: "%.1f%%", server.cpuPercent)
                    )

                    statCard(
                        "Memory",
                        String(format: "%.1f / %.1f GB", server.memoryUsedGB, server.memoryTotalGB)
                    )

                    statCard(
                        "Disk",
                        String(format: "%.1f / %.1f GB", server.diskUsedGB, server.diskTotalGB)
                    )

                    statCard(
                        "Uptime",
                        server.uptime
                    )

                } else if api.loading {

                    ProgressView(
                        "Connecting to server..."
                    )

                } else {

                    ContentUnavailableView(
                        "Server Unavailable",
                        systemImage:
                            "exclamationmark.triangle",
                        description: Text(
                            api.errorMessage ??
                            "Could not connect."
                        )
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Server Control")
        .refreshable {
            await api.loadDashboard()
        }
    }

    private func statCard(
        _ title: String,
        _ value: String
    ) -> some View {

        HStack {

            VStack(alignment: .leading) {

                Text(title)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3.bold())
            }

            Spacer()
        }
        .padding()
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: 16
            )
        )
    }
}

struct PM2View: View {

    @ObservedObject var api: ServerAPI

    var body: some View {

        List(api.dashboard?.processes ?? []) {
            process in

            VStack(alignment: .leading) {

                HStack {

                    Circle()
                        .fill(
                            process.status == "online"
                            ? .green
                            : .red
                        )
                        .frame(
                            width: 8,
                            height: 8
                        )

                    Text(process.name)
                        .font(.headline)

                    Spacer()

                    Text(process.status)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Text(
                    "PM2 ID \(process.id)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {

                    Button("Start") {
                        Task {
                            try? await api.processAction(
                                id: process.id,
                                action: "start"
                            )
                        }
                    }

                    Button("Restart") {
                        Task {
                            try? await api.processAction(
                                id: process.id,
                                action: "restart"
                            )
                        }
                    }

                    Button("Stop", role: .destructive) {
                        Task {
                            try? await api.processAction(
                                id: process.id,
                                action: "stop"
                            )
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("PM2")
        .refreshable {
            await api.loadDashboard()
        }
    }
}

struct DockerView: View {

    @ObservedObject var api: ServerAPI

    var body: some View {

        List(api.dashboard?.containers ?? []) {
            container in

            VStack(alignment: .leading) {

                Text(container.name)
                    .font(.headline)

                Text(
                    container.status ??
                    container.state ??
                    "Unknown"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {

                    Button("Start") {
                        Task {
                            try? await api.dockerAction(
                                name: container.name,
                                action: "start"
                            )
                        }
                    }

                    Button("Restart") {
                        Task {
                            try? await api.dockerAction(
                                name: container.name,
                                action: "restart"
                            )
                        }
                    }

                    Button(
                        "Stop",
                        role: .destructive
                    ) {
                        Task {
                            try? await api.dockerAction(
                                name: container.name,
                                action: "stop"
                            )
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Docker")
        .refreshable {
            await api.loadDashboard()
        }
    }
}

struct GeminiView: View {

    var body: some View {

        ContentUnavailableView(
            "Gemini Monitor",
            systemImage: "sparkles",
            description: Text(
                "Gemini integration will be added next."
            )
        )
        .navigationTitle("Gemini")
    }
}

struct SettingsView: View {

    @ObservedObject var api: ServerAPI

    @State private var serverURL = ""
    @State private var token = ""

    @State private var result = ""

    var body: some View {

        Form {

            Section("Server") {

                TextField(
                    "Server URL",
                    text: $serverURL
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                SecureField(
                    "Server Token",
                    text: $token
                )

                Button("Save") {

                    api.baseURL = serverURL

                    if !token.isEmpty {
                        KeychainManager.save(
                            token: token
                        )
                    }

                    result = "Saved"
                }

                Button("Test Connection") {

                    Task {

                        do {

                            let health =
                                try await api.healthCheck()

                            result = health.ok
                                ? "Server Online"
                                : "Server Error"

                        } catch {

                            result =
                                error.localizedDescription
                        }
                    }
                }

                if !result.isEmpty {

                    Text(result)
                        .foregroundStyle(
                            .secondary
                        )
                }
            }

            Section("Security") {

                Text(
                    "The server token is stored locally in iOS Keychain and is never included in the app source."
                )
                .font(.caption)
            }
        }
        .navigationTitle("Settings")
        .onAppear {

            serverURL = api.baseURL
        }
    }
}
