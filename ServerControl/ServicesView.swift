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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a process", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).accessibilityLabel("Find a process")
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.accessibilityLabel("Clear process search")
                    }
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                // Do not insert an empty row: even an empty custom view can leave stack spacing.
                if api.errorMessage != nil || api.actionNotice != nil {
                    ConnectionNotice(api: api)
                }
                if let date = api.lastUpdated {
                    Text("Last updated: \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if api.dashboard == nil { DashboardPlaceholder(api: api) }
                else {
                    SectionHeading(title: "\(api.dashboard?.processes.count ?? 0) processes",
                                   subtitle: "Confirm a command, then authorize on your iPhone")
                    if processes.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "No processes" : "No matches", systemImage: "terminal",
                                               description: Text(search.isEmpty ? "No PM2 processes were returned by the server." : "Try a different process name."))
                    }
                    ForEach(processes) { process in
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(process.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                        Text("PM2 ID \(process.id)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    StatusPill(title: process.status.capitalized, color: process.status.lowercased() == "online" ? Brand.teal : .orange)
                                }
                                HStack(spacing: 16) {
                                    if let cpu = process.cpu { Label(cpu.percentText, systemImage: "cpu") }
                                    if let memory = process.memoryMB { Label("\(memory.oneDecimal) MB", systemImage: "memorychip") }
                                }.font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Label("Protected controls", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    ControlMenu(name: process.name, target: .process(process.id), disabled: !api.canControl, requestCommand: requestCommand)
                                }
                            }
                        }
                    }
                }
            }.padding(20)
        }
        .background(Brand.background).navigationTitle("PM2")
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
                ConnectionNotice(api: api)
                if let date = api.lastUpdated {
                    Text("Last updated: \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
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
                                    Label("Protected controls", systemImage: "lock.shield").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    ControlMenu(name: container.name, target: .docker, disabled: !api.canControl, requestCommand: requestCommand)
                                }
                            }
                        }
                    }
                }
            }.padding(20)
        }.background(Brand.background).navigationTitle("Docker")
        .searchable(text: $search, prompt: "Find a container")
        .refreshable { await api.loadDashboard() }
    }
}

struct GeminiView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(Brand.accent).padding(.top, 48)
                Text("Gemini monitor").font(.title2.bold())
                Text("A dedicated view for key health and rate limits is planned.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                Surface {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Credentials stay on the server").font(.headline)
                            Text("V2 does not connect to the Gemini monitor or change its authentication.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "lock.shield").foregroundStyle(Brand.teal) }
                }
            }.padding(24)
        }.background(Brand.background).navigationTitle("Gemini")
    }
}
