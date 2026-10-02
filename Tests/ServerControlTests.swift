import XCTest
import LocalAuthentication
@testable import ServerControl

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var requests: [URLRequest] = []
    static var onStart: ((MockURLProtocol) -> Void)?
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        let onStart = Self.onStart
        Self.lock.unlock()
        if let onStart { onStart(self); return }
        do {
            let (status, data) = try XCTUnwrap(handler)(request)
            respond(status: status, data: data)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    func respond(status: Int, data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class DashboardRequestGate {
    private let lock = NSLock()
    private var pending: MockURLProtocol?
    func capture(_ request: MockURLProtocol) {
        lock.lock()
        pending = request
        lock.unlock()
    }
    func complete(with data: Data) {
        lock.lock()
        let request = pending
        pending = nil
        lock.unlock()
        request?.respond(status: 200, data: data)
    }
}

@MainActor
final class ServerControlTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        suite = "ServerControlTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        MockURLProtocol.requests = []
        MockURLProtocol.onStart = nil
        MockURLProtocol.handler = { _ in (200, try JSONEncoder().encode(PreviewFixtures.dashboard)) }
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        MockURLProtocol.handler = nil
        MockURLProtocol.onStart = nil
    }
    private func makeAPI(token: String = "unit-test-placeholder",
                         authorize: @escaping (String) async throws -> Void = { _ in }) -> ServerAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return ServerAPI(session: URLSession(configuration: configuration), defaults: defaults,
                         tokenProvider: { token }, authorize: authorize)
    }
    func testV1ContractAndCredentialBoundaries() async throws {
        let api = makeAPI()
        XCTAssertEqual(api.baseURL, "https://control.admin-ai.site")
        let request = try api.request(path: "/api/dashboard")
        XCTAssertEqual(request.url?.path, "/api/dashboard")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-placeholder")
        XCTAssertNil(try api.request(path: "/api/health", authenticated: false).value(forHTTPHeaderField: "Authorization"))
        await api.loadDashboard()
        XCTAssertEqual(api.dashboard?.processes.first?.id, 1)
        XCTAssertEqual(api.connection, .connected)
        XCTAssertTrue(api.canControl)
    }
    func testMissingTokenSendsNoRequest() async {
        let api = makeAPI(token: "")
        await api.loadDashboard()
        XCTAssertEqual(api.connection, .notConfigured)
        XCTAssertFalse(api.canControl)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testConnectivityFallbackPinsTrustedHostButAuthDoesNotFailOver() async throws {
        let api = makeAPI()
        MockURLProtocol.handler = { request in
            if request.url?.host == "control.admin-ai.site" { throw URLError(.cannotConnectToHost) }
            return (200, try JSONEncoder().encode(PreviewFixtures.dashboard))
        }
        await api.loadDashboard()
        XCTAssertEqual(MockURLProtocol.requests.map { $0.url!.host! }, ["control.admin-ai.site", "ubuntu-lts.tail341977.ts.net"])
        XCTAssertEqual(api.connection, .connected)
        await api.loadDashboard()
        XCTAssertEqual(MockURLProtocol.requests.last?.url?.host, "ubuntu-lts.tail341977.ts.net")
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        let primary = makeAPI()
        MockURLProtocol.requests = []
        MockURLProtocol.handler = { _ in (401, Data()) }
        await primary.loadDashboard()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertEqual(primary.connection, .unauthorized)
        XCTAssertThrowsError(try ServerAPI.validatedBaseURL("https://attacker.example"))
        XCTAssertThrowsError(try ServerAPI.validatedBaseURL("https://control.admin-ai.site:444"))
        XCTAssertThrowsError(try ServerAPI.validatedBaseURL("https://control.admin-ai.site/other"))
    }

    func testBackgroundLocksRequestsAndControlsUntilFreshSnapshot() async {
        let api = makeAPI()
        await api.loadDashboard()
        let date = api.lastUpdated
        api.setAccessAllowed(false)
        MockURLProtocol.requests = []
        await api.loadDashboard()
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
        XCTAssertFalse(api.canControl)
        XCTAssertEqual(api.lastUpdated, date)
        api.setAccessAllowed(true)
        XCTAssertFalse(api.canControl)
        MockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await api.loadDashboard()
        XCTAssertNil(api.errorMessage)
        XCTAssertFalse(api.canControl)
        MockURLProtocol.handler = { _ in (200, try JSONEncoder().encode(PreviewFixtures.dashboard)) }
        await api.loadDashboard()
        XCTAssertTrue(api.canControl)
    }

    func testAppLockCancelKeepsLockedAndAllowsExplicitRetry() async {
        var attempts = 0
        let session = AppSession(authenticate: {
            attempts += 1
            if attempts == 1 { throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue) }
        })
        await session.activate()
        XCTAssertFalse(session.isUnlocked)
        await session.activate()
        XCTAssertEqual(attempts, 1)
        await session.unlock()
        XCTAssertTrue(session.isUnlocked)
        session.lock()
        XCTAssertFalse(session.isUnlocked)
        await session.activate()
        XCTAssertTrue(session.isUnlocked)
        XCTAssertEqual(attempts, 3)
    }

    func testMissingServicesDoesNotInvalidateDashboard() async {
        let api = makeAPI()
        await api.loadDashboard()
        MockURLProtocol.handler = { _ in (501, Data()) }
        await api.loadServices()
        XCTAssertNotNil(api.servicesError)
        XCTAssertEqual(api.connection, .connected)
        XCTAssertNil(api.errorMessage)
        await api.serviceAction(ServiceCommand(kind: .fireClasseraReport, id: "classera-1", name: "Classera 1"))
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.httpMethod == "POST" })
    }

    func testClasseraRequiresAuthorizationAndUsesAllowlistedRoute() async throws {
        var authorizations = [String]()
        let api = makeAPI(authorize: { reason in authorizations.append(reason) })
        let services = Data("""
        {"classera":[{"id":"classera-1","name":"Classera 1","status":"Working","canFire":true}]}
        """.utf8)
        MockURLProtocol.handler = { request in
            if request.httpMethod == "POST" { return (200, Data("{\"ok\":true}".utf8)) }
            if request.url?.path == "/api/services" { return (200, services) }
            return (200, try JSONEncoder().encode(PreviewFixtures.dashboard))
        }
        await api.loadDashboard()
        await api.loadServices()
        await api.serviceAction(ServiceCommand(kind: .fireClasseraReport, id: "classera-1", name: "Classera 1"))
        XCTAssertEqual(authorizations.count, 1)
        XCTAssertTrue(authorizations.first?.contains("real Classera WhatsApp") == true)
        XCTAssertEqual(MockURLProtocol.requests.filter { $0.httpMethod == "POST" }.first?.url?.path, "/api/services/classera/classera-1/fire")
    }
    func testCancelledAuthorizationNeverPosts() async {
        let api = makeAPI(authorize: { _ in throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue) })
        await api.loadDashboard()
        await api.processAction(id: 1, name: "test-service", action: .restart)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.httpMethod == "POST" })
        XCTAssertEqual(api.actionNotice, "Cancelled. No command was sent.")
        XCTAssertFalse(api.actionBusy)
    }
    func testFailedAuthorizationNeverPosts() async {
        let api = makeAPI(authorize: { _ in throw APIError.message("Authentication unavailable") })
        await api.loadDashboard()
        await api.processAction(id: 1, name: "test-service", action: .stop)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertNotNil(api.actionError)
    }
    func testSuccessfulActionUsesExistingRouteThenRefreshes() async {
        var authorizationCount = 0
        let api = makeAPI(authorize: { _ in authorizationCount += 1 })
        MockURLProtocol.handler = { request in
            if request.httpMethod == "POST" { return (200, Data("{\"ok\":true}".utf8)) }
            return (200, try JSONEncoder().encode(PreviewFixtures.dashboard))
        }
        await api.loadDashboard()
        await api.processAction(id: 1, name: "test-service", action: .restart)
        XCTAssertEqual(authorizationCount, 1)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.httpMethod ?? "" }, ["GET", "POST", "GET"])
        XCTAssertEqual(MockURLProtocol.requests[1].url?.path, "/api/process/1/restart")
        XCTAssertNil(api.actionError)
    }
    func testStaleSnapshotDisablesCommands() async {
        let api = makeAPI()
        await api.loadDashboard()
        let date = api.lastUpdated
        MockURLProtocol.handler = { _ in (401, Data()) }
        await api.loadDashboard()
        XCTAssertNotNil(api.dashboard)
        XCTAssertEqual(api.lastUpdated, date)
        XCTAssertEqual(api.connection, .unauthorized)
        XCTAssertFalse(api.canControl)
        await api.processAction(id: 1, name: "test-service", action: .stop)
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.httpMethod == "POST" })
    }
    func testCommandTimeoutNeverRetries() async {
        let api = makeAPI()
        await api.loadDashboard()
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await api.processAction(id: 1, name: "test-service", action: .restart)
        XCTAssertEqual(MockURLProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(api.connection, .unreachable)
        XCTAssertTrue(api.actionError?.contains("may have reached") ?? false)
    }

    func testCancelledCommandRequiresVerificationWithoutFalseOutageOrRetry() async {
        let api = makeAPI()
        await api.loadDashboard()
        MockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await api.processAction(id: 1, name: "test-service", action: .restart)
        XCTAssertEqual(MockURLProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(api.connection, .connected)
        XCTAssertNil(api.errorMessage)
        XCTAssertFalse(api.canControl)
        XCTAssertTrue(api.actionError?.contains("may have reached") == true)
    }

    func testCancelledClasseraAuthorizationDoesNotFire() async throws {
        let api = makeAPI(authorize: { _ in throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue) })
        let services = Data("""
        {"classera":[{"id":"classera-1","name":"Classera 1","status":"Working","canFire":true}]}
        """.utf8)
        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/services" { return (200, services) }
            return (200, try JSONEncoder().encode(PreviewFixtures.dashboard))
        }
        await api.loadDashboard()
        await api.loadServices()
        await api.serviceAction(ServiceCommand(kind: .fireClasseraReport, id: "classera-1", name: "Classera 1"))
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.httpMethod == "POST" })
        XCTAssertEqual(api.actionNotice, "Cancelled. No command was sent.")
    }
    func testSecureURLValidationAndPathEncoding() throws {
        for url in ["http://example.com", "https://user:pass@example.com", "https://example.com?token=x", "https://example.com#fragment"] {
            XCTAssertThrowsError(try ServerAPI.validatedBaseURL(url))
        }
        XCTAssertNoThrow(try ServerAPI.validatedBaseURL(ServerAPI.defaultBaseURL))
        XCTAssertEqual(try ServerAPI.encodedContainerName("name/with?query"), "name%2Fwith%3Fquery")
        XCTAssertThrowsError(try ServerAPI.encodedContainerName(""))
    }
    func testRedirectDelegateRejectsCredentialForwarding() {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let task = URLSession.shared.dataTask(with: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var callbackCalled = false
        NoRedirectDelegate().urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: request) { next in
            callbackCalled = true
            XCTAssertNil(next)
        }
        XCTAssertTrue(callbackCalled)
        task.cancel()
    }
    func testNotificationFoundationHasNoActiveRemoteTransport() {
        XCTAssertFalse(DeferredAlertTransport().isAvailable)
        XCTAssertEqual(AlertCategory.allCases.count, 8)
    }

    func testCancelledRefreshPreservesSuccessfulSnapshotAndConnection() async {
        let api = makeAPI()
        await api.loadDashboard()
        let date = api.lastUpdated
        let name = api.dashboard?.processes.first?.name
        XCTAssertTrue(ServerAPI.isRefreshCancellation(CancellationError()))
        let cancellations: [Error] = [URLError(.cancelled),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)]
        for cancellation in cancellations {
            MockURLProtocol.handler = { _ in throw cancellation }
            await api.loadDashboard()
            XCTAssertEqual(api.connection, .connected)
            XCTAssertEqual(api.lastUpdated, date)
            XCTAssertEqual(api.dashboard?.processes.first?.name, name)
            XCTAssertNil(api.errorMessage)
            XCTAssertFalse(api.loading)
            XCTAssertTrue(api.canControl)
        }
        MockURLProtocol.handler = { _ in (200, try JSONEncoder().encode(PreviewFixtures.dashboard)) }
        await api.loadDashboard()
        XCTAssertEqual(api.connection, .connected)
        XCTAssertNil(api.errorMessage)
    }

    func testCancelledInitialRefreshDoesNotReportConnectionLost() async {
        let api = makeAPI()
        MockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await api.loadDashboard()
        XCTAssertEqual(api.connection, .notConfigured)
        XCTAssertNil(api.errorMessage)
        XCTAssertNil(api.dashboard)
        XCTAssertFalse(api.loading)
    }

    func testCancellationPreservesAnExistingGenuineOutage() async {
        let api = makeAPI()
        await api.loadDashboard()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await api.loadDashboard()
        let error = api.errorMessage
        let date = api.lastUpdated
        XCTAssertEqual(api.connection, .unreachable)
        XCTAssertNotNil(api.dashboard)
        XCTAssertNotNil(error)
        XCTAssertFalse(api.canControl)
        MockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await api.loadDashboard()
        XCTAssertEqual(api.connection, .unreachable)
        XCTAssertEqual(api.errorMessage, error)
        XCTAssertEqual(api.lastUpdated, date)
    }

    func testTabAndPullToRefreshWaitersShareRequestDespiteCancellation() async throws {
        let api = makeAPI()
        await api.loadDashboard()
        MockURLProtocol.requests = []
        let started = expectation(description: "Shared request started")
        let gate = DashboardRequestGate()
        MockURLProtocol.onStart = { request in gate.capture(request); started.fulfill() }
        var firstReturned = false
        var secondReturned = false
        let first = Task { await api.loadDashboard(); firstReturned = true }
        await fulfillment(of: [started], timeout: 5)
        first.cancel() // SwiftUI removes the view that originally requested refresh.
        let joined = expectation(description: "Pull-to-refresh joined")
        let second = Task { joined.fulfill(); await api.loadDashboard(); secondReturned = true }
        await fulfillment(of: [joined], timeout: 5)
        second.cancel() // Another tab disappears while the shared request is pending.
        XCTAssertFalse(firstReturned)
        XCTAssertFalse(secondReturned)
        XCTAssertTrue(api.loading)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertEqual(api.connection, .connected)
        XCTAssertNil(api.errorMessage)
        gate.complete(with: try JSONEncoder().encode(PreviewFixtures.dashboard))
        await first.value
        await second.value
        XCTAssertTrue(firstReturned)
        XCTAssertTrue(secondReturned)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertFalse(api.loading)
        XCTAssertEqual(api.connection, .connected)
        XCTAssertNil(api.errorMessage)
        XCTAssertTrue(api.canControl)
        MockURLProtocol.onStart = nil
        await api.loadDashboard()
        XCTAssertEqual(MockURLProtocol.requests.count, 2) // Next pull starts immediately.
    }

    func testAlreadyCancelledCallerDoesNotStartRefresh() async {
        let api = makeAPI()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await api.loadDashboard()
        }
        await caller.value
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
        XCTAssertEqual(api.connection, .notConfigured)
        XCTAssertNil(api.errorMessage)
        XCTAssertFalse(api.loading)
    }
}
