import SwiftUI
import UIKit

struct LogLine: Codable, Identifiable {
    let id: String
    let stream: String
    let text: String
    let timestamp: String?
}
struct LogSnapshot: Codable {
    let lines: [LogLine]
    let truncated: Bool?
    let fetchedAt: String?
}
enum LogTarget: Hashable {
    case process(Int), docker(String)
    @MainActor var path: String {
        get throws {
            switch self {
            case .process(let id): return "/api/process/\(id)/logs?limit=500"
            case .docker(let name): return "/api/docker/\(try ServerAPI.encodedContainerName(name))/logs?limit=500"
            }
        }
    }
}
struct LogViewer: View {
    @ObservedObject var api: ServerAPI
    let target: LogTarget
    let name: String
    @Environment(\.scenePhase) private var phase
    @State private var snapshot: LogSnapshot?
    @State private var message: String?
    @State private var loading = false
    @State private var live = false
    @State private var search = ""
    @State private var stream = "all"
    private var lines: [LogLine] {
        (snapshot?.lines ?? []).filter {
            (stream == "all" || $0.stream == stream) && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        ScrollViewReader { reader in
            VStack(spacing: 8) {
                HStack {
                    Button(live ? "Pause" : "Live") { live.toggle() }
                    Spacer()
                    Button("Jump to latest") { if let id = lines.last?.id { reader.scrollTo(id, anchor: .bottom) } }
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }.font(.caption).padding(.horizontal)
                Picker("Output", selection: $stream) {
                    Text("All").tag("all"); Text("stdout").tag("stdout"); Text("stderr").tag("stderr")
                }.pickerStyle(.segmented).padding(.horizontal)
                if loading { ProgressView().controlSize(.small) }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                if let fetched = snapshot?.fetchedAt { Text("Last updated: \(fetched)").font(.caption2).foregroundStyle(.secondary) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(lines) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(line.stream).font(.caption2.bold())
                                    if let timestamp = line.timestamp { Text(timestamp).font(.caption2) }
                                }.foregroundStyle(line.stream == "stderr" ? Color.orange : Color.secondary)
                                Text(line.text).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.stream == "stderr" ? Color.orange : Color.primary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    .contextMenu { Button("Copy line") { UIPasteboard.general.string = line.text } }
                            }.padding(8).background(Brand.surface, in: RoundedRectangle(cornerRadius: 8)).id(line.id)
                        }
                        if lines.isEmpty && snapshot != nil { Text("No matching log lines").font(.caption).foregroundStyle(.secondary) }
                        if snapshot?.truncated == true { Text("Showing the latest 500 lines").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.horizontal)
                }.refreshable { await refresh() }
            }.padding(.top, 8)
        }.background(Brand.background).navigationTitle("\(name) logs").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search logs")
        .task {
            snapshot = api.cachedLogs(target)
            await refresh()
        }
        .task(id: live && phase == .active && api.accessAllowed) {
            guard live && phase == .active && api.accessAllowed else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }
    private func refresh() async {
        guard !loading && api.accessAllowed else { return }
        loading = true
        defer { loading = false }
        do { snapshot = try await api.loadLogs(target); message = nil }
        catch {
            guard api.accessAllowed && !ServerAPI.isRefreshCancellation(error) else { return }
            if let http = error as? HTTPFailure, [404, 501].contains(http.status) {
                message = "Logs are not available from this backend yet."
            } else { message = api.friendly(error) }
        }
    }
}

struct ProcessDetailView: View {
    @ObservedObject var api: ServerAPI
    let processID: Int
    let requestCommand: (PendingCommand) -> Void
    private var process: PM2Process? { api.dashboard?.processes.first { $0.id == processID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = process {
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Status", value: p.status.capitalized)
                            LabeledContent("PM2 ID", value: String(p.id))
                            LabeledContent("CPU", value: p.cpu?.percentText ?? "Not reported")
                            LabeledContent("RAM", value: p.memoryMB.map { "\($0.oneDecimal) MB" } ?? "Not reported")
                            LabeledContent("Uptime", value: p.uptime ?? "Not reported")
                            LabeledContent("Restarts", value: p.restartCount.map(String.init) ?? "Not reported")
                            NavigationLink { LogViewer(api: api, target: .process(p.id), name: p.name) } label: { Label("Logs", systemImage: "text.alignleft") }
                            ControlMenu(name: p.name, target: .process(p.id), disabled: !api.canControl, requestCommand: requestCommand)
                        }
                    }
                    SnapshotStamp(date: api.lastUpdated, failed: api.errorMessage != nil)
                } else { Text("This process is no longer in the latest snapshot.").foregroundStyle(.secondary) }
            }.padding(16)
        }.background(Brand.background).navigationTitle(process?.name ?? "Process").navigationBarTitleDisplayMode(.inline)
        .refreshable { await api.loadDashboard() }
    }
}
