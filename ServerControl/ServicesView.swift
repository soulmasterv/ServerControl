import SwiftUI

struct ControlMenu: View {
    let name: String
    let target: PendingCommand.Target
    let disabled: Bool
    let requestCommand: (PendingCommand) -> Void
    var body: some View {
        Menu {
            ForEach(ServerAction.allCases, id: \.rawValue) { action in
                Button(role: action == .stop ? .destructive : nil) {
                    requestCommand(PendingCommand(name: name, target: target, action: action))
                } label: { Label(action.title, systemImage: action.symbol) }
            }
        } label: {
            Label("Control", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Brand.accent.opacity(0.1), in: Capsule())
        }
        .disabled(disabled)
        .accessibilityLabel("Control \(name)")
        .accessibilityHint("Commands require confirmation and device authentication")
    }
}

struct ProcessesView: View {
    @ObservedObject var api: ServerAPI
    let requestCommand: (PendingCommand) -> Void
    @State private var search = ""

    private var processes: [PM2Process] {
        (api.dashboard?.processes ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SearchField(prompt: "Find a process", text: $search)
                    if api.hasNotice { ConnectionNotice(api: api) }
                    SnapshotStamp(date: api.lastUpdated, failed: api.errorMessage != nil)
                }
                if api.dashboard == nil { DashboardPlaceholder(api: api) }
                else {
                    SectionHeading(title: "\(api.dashboard?.processes.count ?? 0) processes",
                                   subtitle: "Confirm controls, then authorize on your iPhone")
                    if processes.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "No processes" : "No matches", systemImage: "terminal",
                                               description: Text(search.isEmpty ? "No PM2 processes were returned by the server." : "Try a different process name."))
                    }
                    ForEach(processes) { process in
                        Surface {
                            VStack(alignment: .leading, spacing: 12) {
                                NavigationLink {
                                    ProcessDetailView(api: api, processID: process.id, requestCommand: requestCommand)
                                } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(process.name).font(.headline)
                                                Text("PM2 ID \(process.id)").font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 8)
                                            StatusPill(title: process.status.capitalized, color: process.status.lowercased() == "online" ? Brand.teal : .orange)
                                        }
                                        HStack(spacing: 16) {
                                            if let cpu = process.cpu { Label(cpu.percentText, systemImage: "cpu") }
                                            if let memory = process.memoryMB { Label("\(memory.oneDecimal) MB", systemImage: "memorychip") }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                HStack {
                                    NavigationLink { LogViewer(api: api, target: .process(process.id), name: process.name) } label: { Label("Logs", systemImage: "text.alignleft").font(.caption) }
                                    Spacer()
                                    ControlMenu(name: process.name, target: .process(process.id), disabled: !api.canControl, requestCommand: requestCommand)
                                }
                            }
                        }
                    }
                }
            }.padding(16)
        }
        .background(Brand.background).navigationTitle("PM2").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await api.loadDashboard() }
    }
}

struct ContainersView: View {
    @ObservedObject var api: ServerAPI
    let requestCommand: (PendingCommand) -> Void
    @State private var search = ""
    private var containers: [DockerContainer] {
        (api.dashboard?.containers ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SearchField(prompt: "Find a container", text: $search)
                    if api.hasNotice { ConnectionNotice(api: api) }
                    SnapshotStamp(date: api.lastUpdated, failed: api.errorMessage != nil)
                }
                if api.dashboard == nil { DashboardPlaceholder(api: api) }
                else {
                    SectionHeading(title: "\(api.dashboard?.containers.count ?? 0) containers",
                                   subtitle: "Run, restart or stop services with confidence")
                    if containers.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "No containers" : "No matches", systemImage: "shippingbox",
                                               description: Text(search.isEmpty ? "No Docker containers were returned by the server." : "Try a different container name."))
                    }
                    ForEach(containers) { container in
                        Surface {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top) {
                                    Text(container.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    StatusPill(title: container.isUnhealthy ? "Unhealthy" : (container.isRunning ? "Running" : (container.state?.capitalized ?? "Stopped")),
                                               color: container.isRunning && !container.isUnhealthy ? Brand.teal : .orange)
                                }
                                if let image = container.image {
                                    Label(image, systemImage: "shippingbox").font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2).textSelection(.enabled)
                                }
                                Text(container.status ?? container.state ?? "Status not reported").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    NavigationLink { LogViewer(api: api, target: .docker(container.name), name: container.name) } label: { Label("Logs", systemImage: "text.alignleft").font(.caption) }
                                    Spacer()
                                    ControlMenu(name: container.name, target: .docker, disabled: !api.canControl, requestCommand: requestCommand)
                                }
                            }
                        }
                    }
                }
            }.padding(16)
        }.background(Brand.background).navigationTitle("Docker").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await api.loadDashboard() }
    }
}

