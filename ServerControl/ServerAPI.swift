import Foundation
import Combine

enum ConnectionState: Equatable {
    case notConfigured, connecting, connected, unreachable, unauthorized, incompatible
    var title: String {
        switch self {
        case .notConfigured: return "Setup needed"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .unreachable: return "Connection lost"
        case .unauthorized: return "Authentication needed"
        case .incompatible: return "Response unavailable"
        }
    }
}

enum ServerAction: String, CaseIterable {
    case start, restart, stop
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .start: return "play.fill"
        case .restart: return "arrow.clockwise"
        case .stop: return "stop.fill"
        }
    }
}

// Never forward bearer credentials through an HTTP redirect.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class ServerAPI: ObservableObject {
    static let defaultBaseURL = "https://ubuntu-lts.tail341977.ts.net/server-control"
    @Published private(set) var dashboard: DashboardResponse?
    @Published private(set) var loading = false
    @Published private(set) var connection: ConnectionState = .notConfigured
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionBusy = false
    @Published private(set) var actionProgress = ""
    @Published var actionError: String?
    @Published var actionNotice: String?
    @Published private(set) var hasSavedToken = false

    private let session: URLSession
    private let tokenProvider: () -> String
    private let authorize: (String) async throws -> Void
    private let defaults: UserDefaults
    private var previewMode = false

    init(session: URLSession? = nil, defaults: UserDefaults = .standard,
         tokenProvider: @escaping () -> String = { KeychainManager.load() },
         authorize: @escaping (String) async throws -> Void = { reason in
             try await DeviceAuthorization.authorize(reason: reason)
         }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        self.defaults = defaults
        self.tokenProvider = tokenProvider
        self.authorize = authorize
        hasSavedToken = !tokenProvider().isEmpty
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            previewMode = true
            dashboard = PreviewFixtures.dashboard
            connection = .connected
            hasSavedToken = true
            lastUpdated = Date()
        }
        #endif
    }

    var baseURL: String { defaults.string(forKey: "serverURL") ?? Self.defaultBaseURL }
    var canControl: Bool { connection == .connected && !loading && !actionBusy && hasSavedToken }

    static func validatedBaseURL(_ value: String) throws -> URL {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: clean), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, let url = components.url else {
            throw APIError.message("Use an HTTPS server URL without a username, password, query or fragment.")
        }
        return url
    }

    func saveConnection(url: String, replacementToken: String) throws {
        guard !loading && !actionBusy else { throw APIError.message("Wait for the current request to finish.") }
        let valid = try Self.validatedBaseURL(url)
        let cleanToken = replacementToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty { try KeychainManager.save(token: cleanToken) }
        defaults.set(valid.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "serverURL")
        hasSavedToken = !tokenProvider().isEmpty
        dashboard = nil
        lastUpdated = nil
        errorMessage = nil
        actionNotice = nil
        connection = .notConfigured
    }

    func removeToken() throws {
        guard !loading && !actionBusy else { throw APIError.message("Wait for the current request to finish.") }
        try KeychainManager.delete()
        hasSavedToken = false
        dashboard = nil
        lastUpdated = nil
        errorMessage = nil
        actionNotice = nil
        connection = .notConfigured
    }

    // Preserve the original API routes and camelCase models.
    func request(path: String, method: String = "GET", authenticated: Bool = true) throws -> URLRequest {
        let base = try Self.validatedBaseURL(baseURL)
        let clean = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.hasPrefix("/api/"), let url = URL(string: clean + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            let token = tokenProvider()
            guard !token.isEmpty else { throw APIError.message("Add your server token in Settings to connect.") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func loadDashboard() async {
        guard !previewMode && !loading else { return }
        hasSavedToken = !tokenProvider().isEmpty
        guard hasSavedToken else {
            connection = .notConfigured
            errorMessage = "Add your server token in Settings."
            return
        }
        loading = true
        if dashboard == nil { connection = .connecting }
        defer { loading = false }
        do {
            let (data, response) = try await session.data(for: request(path: "/api/dashboard"))
            try validate(response)
            dashboard = try JSONDecoder().decode(DashboardResponse.self, from: data)
            lastUpdated = Date()
            connection = .connected
            errorMessage = nil
        } catch {
            if let httpError = error as? HTTPFailure, [401, 403].contains(httpError.status) {
                connection = .unauthorized
            } else if error is DecodingError {
                connection = .incompatible
            } else {
                connection = .unreachable
            }
            errorMessage = friendly(error)
        }
    }

    func healthCheck() async throws -> HealthResponse {
        let (data, response) = try await session.data(for: request(path: "/api/health", authenticated: false))
        try validate(response)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    static func encodedContainerName(_ name: String) throws -> String {
        guard !name.isEmpty, let encoded = name.addingPercentEncoding(withAllowedCharacters:
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) else {
            throw APIError.message("The container name is invalid.")
        }
        return encoded
    }

    func processAction(id: Int, name: String, action: ServerAction) async {
        await performAction(path: "/api/process/\(id)/\(action.rawValue)", name: name, action: action)
    }

    func dockerAction(name: String, action: ServerAction) async {
        do {
            let encoded = try Self.encodedContainerName(name)
            await performAction(path: "/api/docker/\(encoded)/\(action.rawValue)", name: name, action: action)
        } catch { actionError = friendly(error) }
    }

    private func performAction(path: String, name: String, action: ServerAction) async {
        guard !previewMode else { actionError = "Preview mode cannot send server commands."; return }
        guard canControl else { actionError = "Refresh the dashboard and reconnect before sending a command."; return }
        actionBusy = true
        actionProgress = "Authorizing \(action.rawValue)…"
        actionNotice = nil
        defer { actionBusy = false; actionProgress = "" }
        var commandStarted = false
        do {
            try await authorize("\(action.title) \(name) on your server.")
            let command = try request(path: path, method: "POST")
            actionProgress = "Sending \(action.rawValue)…"
            commandStarted = true
            let (data, response) = try await session.data(for: command)
            try validate(response)
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["ok"] as? Bool == false || object["success"] as? Bool == false {
                throw APIError.message("The server declined the command.")
            }
            actionNotice = "\(action.title) requested for \(name)."
            await loadDashboard()
        } catch {
            if DeviceAuthorization.isCancellation(error) {
                actionNotice = "Cancelled. No command was sent."
            } else if commandStarted && error is URLError {
                actionError = "The connection was interrupted. The command may have reached the server. Refresh to check before trying again."
                connection = .unreachable
                errorMessage = "Refresh to verify the server state."
            } else {
                actionError = friendly(error)
                if let http = error as? HTTPFailure, [401, 403].contains(http.status) {
                    connection = .unauthorized
                    errorMessage = actionError
                }
            }
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw HTTPFailure(status: http.statusCode) }
    }

    func friendly(_ error: Error) -> String {
        if let http = error as? HTTPFailure {
            switch http.status {
            case 401, 403: return "Authentication failed. Check your server token in Settings."
            case 300...399: return "The server redirected this request. Check the HTTPS URL in Settings."
            default: return "The server returned HTTP \(http.status). Try refreshing shortly."
            }
        }
        if error is DecodingError { return "The server response could not be read. Your last snapshot is still available." }
        if let url = error as? URLError {
            if url.code == .timedOut { return "The server took too long to respond. Pull down to retry." }
            return "Cannot reach the server. Check your internet connection and try again."
        }
        return error.localizedDescription
    }
}

struct HTTPFailure: Error { let status: Int }
enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
