import SwiftUI

struct HomeView: View {
    @ObservedObject var api: ServerAPI
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 14), count: dynamicType.isAccessibilitySize ? 1 : 2) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ConnectionNotice(api: api)
                if let dashboard = api.dashboard {
                    serverCard(dashboard.server)
                    SectionHeading(title: "Resources", subtitle: "The latest snapshot from your server")
                    LazyVGrid(columns: columns, spacing: 14) {
                        ResourceCard(title: "CPU", symbol: "cpu", value: dashboard.server.cpuPercent.percentText,
                                     detail: "Processor utilization", percent: dashboard.server.cpuPercent, tint: Brand.accent)
                        ResourceCard(title: "Memory", symbol: "memorychip", value: "\(dashboard.server.memoryUsedGB.oneDecimal) GB",
                                     detail: "of \(dashboard.server.memoryTotalGB.oneDecimal) GB",
                                     percent: ratio(dashboard.server.memoryUsedGB, dashboard.server.memoryTotalGB), tint: Brand.teal)
                        ResourceCard(title: "Disk", symbol: "internaldrive", value: "\(dashboard.server.diskUsedGB.oneDecimal) GB",
                                     detail: "of \(dashboard.server.diskTotalGB.oneDecimal) GB",
                                     percent: ratio(dashboard.server.diskUsedGB, dashboard.server.diskTotalGB), tint: .orange)
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Uptime", systemImage: "clock").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                Text(dashboard.server.uptime).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                                Text("Since last reboot").font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                        }
                    }
                    SectionHeading(title: "Services", subtitle: "Open PM2 or Docker to manage each service")
                    Surface {
                        VStack(spacing: 18) {
                            serviceSummary("PM2 processes", symbol: "terminal", active: dashboard.processes.filter { $0.status.lowercased() == "online" }.count,
                                           total: dashboard.processes.count, color: Brand.accent)
                            Divider()
                            serviceSummary("Docker containers", symbol: "shippingbox", active: dashboard.containers.filter { $0.isRunning }.count,
                                           total: dashboard.containers.count, color: Brand.teal)
                        }
                    }
                } else { DashboardPlaceholder(api: api) }
            }.padding(20)
        }
        .background(Brand.background)
        .navigationTitle("Server Control")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await api.loadDashboard() } } label: {
                    if api.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }.disabled(api.loading || api.actionBusy).accessibilityLabel("Refresh dashboard")
            }
        }
        .refreshable { await api.loadDashboard() }
    }

    private func ratio(_ used: Double, _ total: Double) -> Double { total > 0 ? used / total * 100 : 0 }

    private func serverCard(_ server: ServerStats) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    BrandMark(size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(server.hostname).font(.title2.bold()).textSelection(.enabled)
                        Text("Ubuntu • Server overview").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    StatusPill(title: api.connection.title, color: api.connection == .connected ? Brand.teal : .orange)
                    Spacer()
                    if let date = api.lastUpdated {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(api.connection == .connected ? "Last refreshed" : "Snapshot from").font(.caption2).foregroundStyle(.secondary)
                            Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func serviceSummary(_ title: String, symbol: String, active: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text("\(active) / \(total)").font(.subheadline.bold()).monospacedDigit()
            Text("running").font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct ResourceCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let percent: Double
    let tint: Color
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(value).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: percent.boundedPercent, total: 100).tint(percent >= 90 ? .orange : tint)
                    .accessibilityLabel("\(title) utilization")
                    .accessibilityValue("\(percent.percentText)")
                Text(percent >= 90 ? "High utilization" : "Current utilization").font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        }
    }
}

extension DockerContainer {
    var isRunning: Bool {
        if let state { return state.lowercased() == "running" }
        return status?.lowercased().hasPrefix("up") ?? false
    }
    var isUnhealthy: Bool { status?.lowercased().contains("unhealthy") ?? false }
}
