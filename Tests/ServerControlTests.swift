import XCTest
import LocalAuthentication
@testable import ServerControl

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var requests: [URLRequest] = []
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let (status, data) = try XCTUnwrap(handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class ServerControlTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        suite = "ServerControlTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        MockURLProtocol.requests = []
        MockURLProtocol.handler = { _ in (200, try JSONEncoder().encode(PreviewFixtures.dashboard)) }
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        MockURLProtocol.handler = nil
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
        XCTAssertEqual(api.baseURL, "https://ubuntu-lts.tail341977.ts.net/server-control")
        let request = try api.request(path: "/api/dashboard")
        XCTAssertEqual(request.url?.path, "/server-control/api/dashboard")
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
        XCTAssertEqual(MockURLProtocol.requests[1].url?.path, "/server-control/api/process/1/restart")
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
}
