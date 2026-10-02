import SwiftUI

enum ServicePage: String, CaseIterable, Identifiable {
    case gemini, classera, padel
    var id: String { rawValue }
    var title: String { rawValue == "gemini" ? "Gemini Monitor" : rawValue.capitalized }
    var symbol: String {
        switch self { case .gemini: return "sparkles"; case .classera: return "graduationcap"; case .padel: return "sportscourt" }
    }
    var detail: String {
        switch self {
        case .gemini: return "Key health and server-side checks"
        case .classera: return "Schedulers and report delivery"
        case .padel: return "Watcher, bot and WhatsApp health"
        }
    }
}
struct ServiceCatalogView: View {
    @ObservedObject var api: ServerAPI
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(ServicePage.allCases) { page in
                    NavigationLink {
                        ServiceDetailView(api: api, page: page)
                    } label: {
                        Surface {
                            HStack(spacing: 16) {
                                Image(systemName: page.symbol).font(.title2).foregroundStyle(Brand.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(page.title).font(.headline)
                                    Text(page.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(Brand.background).navigationTitle("Services")
    }
}
struct ServiceDetailView: View {
    @ObservedObject var api: ServerAPI
    let page: ServicePage
    @State private var pending: ServiceCommand?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if api.servicesLoading { ProgressView("Updating service status") }
                if let error = api.servicesError {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await api.loadServices() } }.buttonStyle(.bordered)
                }
                if let date = api.servicesUpdatedAt {
                    Text("Last updated: \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                if api.serviceSnapshot != nil {
                    serviceContent
                } else if !api.servicesLoading && api.servicesError == nil {
                    Text("Service status is not available yet.").foregroundStyle(.secondary)
                }
            }.padding(20)
        }.background(Brand.background).navigationTitle(page.title)
        .task { await api.loadServices() }
        .refreshable { await api.loadServices() }
        .confirmationDialog(pending?.title ?? "Confirm", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { command in
            Button(command.kind == .fireClasseraReport ? "Send WhatsApp report" : "Test Key", role: command.kind == .fireClasseraReport ? .destructive : nil) {
                Task { await api.serviceAction(command) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { command in Text(command.explanation) }
    }
    @ViewBuilder private var serviceContent: some View {
        switch page {
        case .gemini:
            if let health = api.serviceSnapshot?.geminiHealth { Label(health, systemImage: "heart.text.square").font(.subheadline) }
            ForEach(api.serviceSnapshot?.gemini ?? []) { key in
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        heading(key.name, status: key.status)
                        detail("Authentication check", key.lastAuthenticationCheck)
                        detail("Generation check", key.lastGenerationCheck)
                        Button("Test Key") { pending = ServiceCommand(kind: .testGeminiKey, id: key.id, name: key.name) }
                            .buttonStyle(.bordered).disabled(key.canTest != true || !api.canControl || api.servicesLoading || api.servicesError != nil)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if api.serviceSnapshot?.gemini?.isEmpty != false { Text("The monitor has not reported any key status.").foregroundStyle(.secondary) }
        case .classera:
            ForEach(api.serviceSnapshot?.classera ?? []) { service in
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        heading(service.name, status: service.status)
                        detail("Scheduler", service.schedulerStatus)
                        detail("Webhook", service.webhookStatus)
                        detail("Last run", service.lastRun)
                        detail("Last report", service.lastReport)
                        Button("Send WhatsApp report", role: .destructive) {
                            pending = ServiceCommand(kind: .fireClasseraReport, id: service.id, name: service.name)
                        }.buttonStyle(.bordered).disabled(service.canFire != true || !api.canControl || api.servicesLoading || api.servicesError != nil)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if api.serviceSnapshot?.classera?.isEmpty != false { Text("Classera status has not been reported.").foregroundStyle(.secondary) }
        case .padel:
            ForEach(api.serviceSnapshot?.padel ?? []) { component in
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        heading(component.name, status: component.status)
                        detail("WhatsApp delivery", component.deliveryStatus)
                        detail("Last notification", component.lastNotification)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if api.serviceSnapshot?.padel?.isEmpty != false { Text("Padel status has not been reported.").foregroundStyle(.secondary) }
        }
    }
    private func heading(_ name: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            StatusPill(title: status, color: ["working", "online", "healthy", "running"].contains(status.lowercased()) ? Brand.teal : .orange)
        }
    }
    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        if let value { Text("\(title): \(value)").font(.caption).foregroundStyle(.secondary) }
    }
}
