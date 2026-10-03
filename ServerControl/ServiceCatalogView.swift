import SwiftUI

enum ServicePage: String, CaseIterable, Identifiable, Codable {
    case gemini, classera, padel
    var id: String { rawValue }
    var title: String { self == .gemini ? "Gemini Monitor" : rawValue.capitalized }
    var symbol: String { switch self { case .gemini: return "sparkles"; case .classera: return "graduationcap"; case .padel: return "sportscourt" } }
}
struct ServiceDetailView: View {
    @ObservedObject var api: ServerAPI
    let page: ServicePage
    @State private var pending: ServiceCommand?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label(page.title, systemImage: page.symbol).font(.headline); Spacer(); StatusBadge(status: api.serviceStatus(page)) }
                        Text(api.serviceSummary(page)).font(.subheadline).foregroundStyle(.secondary)
                        if page == .gemini, let health = api.serviceSnapshot?.geminiHealth { HStack { Text("Monitor").font(.caption).foregroundStyle(.secondary); StatusBadge(status: health) } }
                        SnapshotStamp(date: api.servicesUpdatedAt, failed: api.servicesError != nil)
                    }
                }
                if let error = api.servicesError { Label(error, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                if api.serviceSnapshot == nil {
                    FeatureUnavailable(title: api.servicesLoading ? "Loading service health" : "Service data unavailable", message: "The authenticated backend must report this integration. Refresh to check again.")
                } else { serviceContent }
            }.padding(16)
        }.background(Brand.background).navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { FavoriteButton(target: .service(page)) }
            ToolbarItem(placement: .topBarTrailing) { RefreshIndicator(loading: api.servicesLoading) { Task { await api.loadServices() } } }
        }
        .task { await api.ensureServicesFresh() }.refreshable { await api.loadServices() }
        .confirmationDialog(pending?.title ?? "Confirm", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { command in
            Button(command.kind == .fireClasseraReport ? "Send report for \(command.name)" : "Test \(command.name)", role: command.kind == .fireClasseraReport ? .destructive : nil) { Task { await api.serviceAction(command) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0.explanation) }
    }
    @ViewBuilder private var serviceContent: some View {
        switch page {
        case .gemini:
            let keys = api.serviceSnapshot?.gemini ?? []
            if keys.isEmpty { FeatureUnavailable(title: "No key status", message: "The monitor has not reported key health.") }
            ForEach(keys) { key in
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(safeGeminiName(key)).font(.subheadline.weight(.semibold)); Spacer()
                            StatusBadge(status: key.status)
                            if reason(key.canTest) == nil { Button("Test") { pending = ServiceCommand(kind: .testGeminiKey, id: key.id, name: safeGeminiName(key)) }.font(.subheadline).frame(minWidth: 44, minHeight: 44) }
                        }
                        HStack { Text("Auth \(HumanTime.label(key.lastAuthenticationCheck))"); Spacer(); Text("Generation \(HumanTime.label(key.lastGenerationCheck))") }.font(.caption).foregroundStyle(.secondary)
                        if let why = reason(key.canTest) { Text("Test unavailable: \(why)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        case .classera:
            let instances = api.serviceSnapshot?.classera ?? []
            if instances.isEmpty { FeatureUnavailable(title: "No Classera status", message: "Scheduler and report information has not been reported.") }
            ForEach(instances) { service in
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(service.name).font(.headline); Spacer(); StatusBadge(status: service.status) }
                        HStack { componentState("Scheduler", service.schedulerStatus); Spacer(); componentState("Webhook", service.webhookStatus) }
                        HStack { timeRow("Last run", service.lastRun); Spacer(); timeRow("Last report", service.lastReport) }
                        Divider()
                        if let why = reason(service.canFire) { Label("Report unavailable: \(why)", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                        else { Button { pending = ServiceCommand(kind: .fireClasseraReport, id: service.id, name: service.name) } label: { Label("Send WhatsApp Report", systemImage: "paperplane").font(.subheadline.weight(.medium)).frame(minHeight: 44) } }
                    }
                }
            }
        case .padel:
            let components = api.serviceSnapshot?.padel ?? []
            if components.isEmpty { FeatureUnavailable(title: "No Padel status", message: "Application and delivery health has not been reported.") }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(components) { component in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Label(component.name.replacingOccurrences(of: "Padel ", with: ""), systemImage: component.isWhatsApp ? "message" : "server.rack").font(.subheadline.weight(.medium)); Spacer(); StatusBadge(status: component.status) }
                            if component.isWhatsApp {
                                HStack { Text("Delivery / billing").font(.caption).foregroundStyle(.secondary); Spacer(); StatusBadge(status: component.deliveryStatus ?? "Unknown") }
                                Text("Delivery can fail while the application remains online.").font(.caption).foregroundStyle(.secondary)
                            }
                            if component.lastNotification != nil { Text("Last notification: \(HumanTime.label(component.lastNotification))").font(.caption).foregroundStyle(.secondary) }
                        }
                        if component.id != components.last?.id { Divider() }
                    }
                }
            }
        }
    }
    private func safeGeminiName(_ key: GeminiKeyStatus) -> String {
        // Never render monitor-provided names that could contain an actual key.
        let suffix = key.id.replacingOccurrences(of: "key-", with: "")
        return Int(suffix).map { (1...10).contains($0) ? "Gemini \($0)" : "Gemini key" } ?? "Gemini key"
    }
    private func reason(_ capable: Bool?) -> String? {
        if capable != true { return "not enabled by the backend" }
        if api.actionBusy { return "another action is in progress" }
        if api.servicesLoading { return "checking the latest status" }
        if api.servicesError != nil { return "service status needs verification" }
        if !api.canControl { return "refresh and authenticate your connection" }
        return nil
    }
    private func componentState(_ title: String, _ state: String?) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); StatusBadge(status: state ?? "Unknown") } }
    private func timeRow(_ title: String, _ date: String?) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(HumanTime.label(date)).font(.caption.weight(.medium)) } }
}
