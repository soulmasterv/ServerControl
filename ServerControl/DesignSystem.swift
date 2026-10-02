import SwiftUI

enum Brand {
    static let accent = Color(red: 0.34, green: 0.35, blue: 0.92)
    static let teal = Color(red: 0.04, green: 0.66, blue: 0.62)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: "server.rack")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Brand.accent, Brand.teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(20).background(Brand.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConnectionNotice: View {
    @ObservedObject var api: ServerAPI
    var body: some View {
        if let message = api.errorMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: api.connection == .unauthorized ? "lock.shield" : "wifi.exclamationmark")
                    .foregroundStyle(.orange).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(api.connection.title).font(.subheadline.bold())
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    if api.dashboard != nil { Text("Showing the last successful snapshot. Controls are paused.").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(16).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
        }
        if let notice = api.actionNotice {
            Label(notice, systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DashboardPlaceholder: View {
    @ObservedObject var api: ServerAPI
    var body: some View {
        VStack(spacing: 16) {
            if api.loading {
                ProgressView().controlSize(.large).tint(Brand.accent)
                Text("Connecting to your server").font(.headline)
                Text("Fetching the latest snapshot…").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Image(systemName: api.hasSavedToken ? "wifi.exclamationmark" : "lock.shield")
                    .font(.system(size: 40)).foregroundStyle(Brand.accent)
                Text(api.hasSavedToken ? "Let's reconnect" : "Your server, at a glance").font(.title3.bold())
                Text(api.errorMessage ?? "Add your server token in Settings to see your server.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if api.hasSavedToken {
                    Button("Try again") { Task { await api.loadDashboard() } }.buttonStyle(.borderedProminent)
                } else {
                    Text("Settings → Server connection").font(.caption.weight(.medium)).foregroundStyle(Brand.accent)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60).padding(.horizontal, 20)
    }
}

extension Double {
    var percentText: String { String(format: "%.1f%%", self) }
    var oneDecimal: String { String(format: "%.1f", self) }
    var boundedPercent: Double { isFinite ? min(max(self, 0), 100) : 0 }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
