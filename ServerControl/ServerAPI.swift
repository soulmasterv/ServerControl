import Foundation
import Combine

@MainActor
final class ServerAPI: ObservableObject {

    static let defaultBaseURL =
        "https://ubuntu-lts.tail341977.ts.net/server-control"

    @Published var dashboard: DashboardResponse?
    @Published var loading = false
    @Published var errorMessage: String?

    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: "serverURL")
            ?? Self.defaultBaseURL
        }

        set {
            UserDefaults.standard.set(newValue, forKey: "serverURL")
        }
    }

    var token: String {
        KeychainManager.load()
    }

    private func request(
        path: String,
        method: String = "GET",
        authenticated: Bool = true
    ) throws -> URLRequest {

        let cleanBase = baseURL.hasSuffix("/")
            ? String(baseURL.dropLast())
            : baseURL

        guard let url = URL(string: cleanBase + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)

        request.httpMethod = method
        request.timeoutInterval = 15

        if authenticated {
            let token = self.token

            if !token.isEmpty {
                request.setValue(
                    "Bearer \(token)",
                    forHTTPHeaderField: "Authorization"
                )
            }
        }

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        return request
    }

    func loadDashboard() async {

        loading = true
        errorMessage = nil

        defer {
            loading = false
        }

        do {

            let request = try request(
                path: "/api/dashboard"
            )

            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard let http =
                    response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard http.statusCode == 200 else {

                if http.statusCode == 401 {
                    throw APIError.message(
                        "Authentication failed. Check your server token."
                    )
                }

                throw APIError.message(
                    "Server returned HTTP \(http.statusCode)"
                )
            }

            dashboard = try JSONDecoder()
                .decode(
                    DashboardResponse.self,
                    from: data
                )

        } catch {

            errorMessage = error.localizedDescription

        }
    }

    func healthCheck() async throws -> HealthResponse {

        let request = try request(
            path: "/api/health",
            authenticated: false
        )

        let (data, response) =
            try await URLSession.shared.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            throw APIError.message(
                "Server health check failed."
            )
        }

        return try JSONDecoder()
            .decode(
                HealthResponse.self,
                from: data
            )
    }

    func processAction(
        id: Int,
        action: String
    ) async throws {

        let request = try request(
            path: "/api/process/\(id)/\(action)",
            method: "POST"
        )

        try await performAction(request)
        await loadDashboard()
    }

    func dockerAction(
        name: String,
        action: String
    ) async throws {

        let encoded =
            name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? name

        let request = try request(
            path: "/api/docker/\(encoded)/\(action)",
            method: "POST"
        )

        try await performAction(request)
        await loadDashboard()
    }

    private func performAction(
        _ request: URLRequest
    ) async throws {

        let (_, response) =
            try await URLSession.shared.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else {
            throw APIError.message(
                "Server command failed."
            )
        }
    }
}

enum APIError: LocalizedError {

    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}
