import Foundation
import XCTest
@testable import X5

@MainActor
final class CurrentUserSessionIsolationTests: XCTestCase {
    private let accountA = "11111111-1111-4111-8111-111111111111"
    private let accountB = "22222222-2222-4222-8222-222222222222"

    override func tearDown() {
        ProfileIsolationURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeUser(account: @escaping @MainActor () -> String?) -> CurrentUser {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileIsolationURLProtocol.self]
        return CurrentUser(session: URLSession(configuration: configuration), sessionUserID: account, restoreCache: false)
    }

    func testDelayedPreviousAccountResponseCannotOverwriteCurrentProfileOrCache() async {
        var currentAccount: String? = accountA
        let user = makeUser { currentAccount }
        let oldRequestStarted = expectation(description: "request A held")
        var delayed: ProfileIsolationURLProtocol?
        ProfileIsolationURLProtocol.handler = { request in
            if request.request.value(forHTTPHeaderField: "Authorization") == "Bearer A" {
                delayed = request
                oldRequestStarted.fulfill()
            } else {
                request.complete(userID: self.accountB, credits: 200)
            }
        }
        let oldLoad = Task { await user.load(userId: accountA, accessToken: "A") }
        await fulfillment(of: [oldRequestStarted], timeout: 5)
        currentAccount = accountB
        let newLoaded = await user.load(userId: accountB, accessToken: "B")
        XCTAssertTrue(newLoaded)
        delayed?.complete(userID: accountA, credits: 100)
        let oldLoaded = await oldLoad.value
        XCTAssertFalse(oldLoaded)
        XCTAssertEqual(user.profile?.id, accountB)
        XCTAssertEqual(user.profile?.credits, 200)
    }

    func testSignedOutResponseCannotRestorePrivateProfile() async {
        var currentAccount: String? = accountA
        let user = makeUser { currentAccount }
        let started = expectation(description: "request held")
        var delayed: ProfileIsolationURLProtocol?
        ProfileIsolationURLProtocol.handler = { request in delayed = request; started.fulfill() }
        let load = Task { await user.load(userId: accountA, accessToken: "A") }
        await fulfillment(of: [started], timeout: 5)
        currentAccount = nil
        NotificationCenter.default.post(name: .x5UserDidSignOut, object: nil)
        delayed?.complete(userID: accountA, credits: 100)
        let loaded = await load.value
        XCTAssertFalse(loaded)
        XCTAssertNil(user.profile)
    }

    func testConcurrentSameAccountLoadsRemainValidForLoginRouting() async {
        let user = makeUser { self.accountA }
        let started = expectation(description: "both requests held")
        started.expectedFulfillmentCount = 2
        let requests = HeldProfileRequests()
        ProfileIsolationURLProtocol.handler = { request in requests.add(request); started.fulfill() }
        let first = Task { await user.load(userId: accountA, accessToken: "A") }
        let second = Task { await user.load(userId: accountA, accessToken: "refreshed-A") }
        await fulfillment(of: [started], timeout: 5)
        for request in requests.snapshot { request.complete(userID: accountA, credits: 100) }
        let firstLoaded = await first.value
        let secondLoaded = await second.value
        XCTAssertTrue(firstLoaded)
        XCTAssertTrue(secondLoaded)
        XCTAssertEqual(user.profile?.id, accountA)
    }
}

private final class HeldProfileRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProfileIsolationURLProtocol] = []
    func add(_ value: ProfileIsolationURLProtocol) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshot: [ProfileIsolationURLProtocol] { lock.lock(); defer { lock.unlock() }; return values }
}

private final class ProfileIsolationURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((ProfileIsolationURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}

    func complete(userID: String, credits: Int) {
        let data = Data("[{\"id\":\"\(userID)\",\"credits\":\(credits),\"plan\":\"free\"}]".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
