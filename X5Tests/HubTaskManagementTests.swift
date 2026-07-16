import XCTest
@testable import X5

final class HubTaskManagementTests: XCTestCase {
    private let ownerID = "f3eea23f-0aeb-405b-ab35-2c53173b7a8f"
    private let taskID = "11111111-1111-4111-8111-111111111111"

    override func tearDown() {
        HubTaskURLProtocol.handler = nil
        super.tearDown()
    }

    func testOwnerPublicationActionOnlyAllowsOpenCancelledTransitions() {
        XCTAssertEqual(HubTaskPublicationAction.forStatus("open"), .deactivate)
        XCTAssertEqual(HubTaskPublicationAction.forStatus("cancelled"), .reactivate)
        XCTAssertNil(HubTaskPublicationAction.forStatus("in_progress"))
        XCTAssertNil(HubTaskPublicationAction.forStatus("done"))
    }

    func testTaskStatusPresentationUsesLiveDatabaseDoneStatus() {
        XCTAssertEqual(
            HubTaskStatusPresentation.localizationKey(for: "done"),
            "my_tasks_status_completed"
        )
        XCTAssertEqual(
            HubTaskStatusPresentation.localizationKey(for: "in_progress"),
            "my_tasks_status_in_progress"
        )
    }

    @MainActor
    func testLoadMyTasksUsesBearerOwnerFilterAndKeepsEveryStatus() async throws {
        var capturedRequest: URLRequest?
        HubTaskURLProtocol.handler = { request in
            capturedRequest = request
            return Self.response(
                for: request,
                body: """
                [
                  {"id":"11111111-1111-4111-8111-111111111111","author_id":"f3eea23f-0aeb-405b-ab35-2c53173b7a8f","title":"Open","status":"open"},
                  {"id":"22222222-2222-4222-8222-222222222222","author_id":"f3eea23f-0aeb-405b-ab35-2c53173b7a8f","title":"Cancelled","status":"cancelled"}
                ]
                """
            )
        }
        let service = makeService()

        let tasks = await service.loadMyTasks(
            authorId: ownerID,
            accessToken: "owner-token"
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        assertOwnerScope(request)
        XCTAssertEqual(queryValue("select", in: request), "*")
        XCTAssertNil(queryValue("status", in: request))
        XCTAssertEqual(tasks.map(\.status), ["open", "cancelled"])
        XCTAssertEqual(service.myTasks, tasks)
    }

    @MainActor
    func testUpdateTaskPatchesExistingOwnedRowWithoutCreatingAnotherTask() async throws {
        var capturedRequest: URLRequest?
        HubTaskURLProtocol.handler = { request in
            capturedRequest = request
            return Self.response(
                for: request,
                body: """
                [{"id":"11111111-1111-4111-8111-111111111111","author_id":"f3eea23f-0aeb-405b-ab35-2c53173b7a8f","title":"Updated","description":"New details","budget":"75000","category":"design","status":"open"}]
                """
            )
        }
        let service = makeService()

        let updated = await service.updateTask(
            taskId: taskID,
            authorId: ownerID,
            title: "Updated",
            description: "New details",
            budget: "75000",
            category: "design",
            deadline: nil,
            accessToken: "owner-token"
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertNotEqual(request.httpMethod, "POST")
        assertOwnedRowScope(request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=representation")
        let body = try requestJSON(request)
        XCTAssertEqual(body["title"] as? String, "Updated")
        XCTAssertEqual(body["description"] as? String, "New details")
        XCTAssertEqual(body["budget"] as? String, "75000")
        XCTAssertEqual(body["category"] as? String, "design")
        XCTAssertTrue(body["deadline"] is NSNull)
        XCTAssertNil(body["author_id"])
        XCTAssertNil(body["status"])
        XCTAssertEqual(updated?.title, "Updated")
        XCTAssertEqual(service.myTasks.first?.title, "Updated")
    }

    @MainActor
    func testSetTaskActiveOnlyTransitionsBetweenOpenAndCancelled() async throws {
        var capturedRequests: [URLRequest] = []
        HubTaskURLProtocol.handler = { request in
            capturedRequests.append(request)
            let body = try self.requestJSON(request)
            let status = try XCTUnwrap(body["status"] as? String)
            return Self.response(
                for: request,
                body: """
                [{"id":"11111111-1111-4111-8111-111111111111","author_id":"f3eea23f-0aeb-405b-ab35-2c53173b7a8f","title":"Task","status":"\(status)"}]
                """
            )
        }
        let service = makeService()

        let cancelled = await service.setTaskActive(
            taskId: taskID,
            authorId: ownerID,
            isActive: false,
            accessToken: "owner-token"
        )
        let reopened = await service.setTaskActive(
            taskId: taskID,
            authorId: ownerID,
            isActive: true,
            accessToken: "owner-token"
        )

        XCTAssertEqual(capturedRequests.count, 2)
        for request in capturedRequests {
            XCTAssertEqual(request.httpMethod, "PATCH")
            assertOwnedRowScope(request)
        }
        XCTAssertEqual(try requestJSON(capturedRequests[0])["status"] as? String, "cancelled")
        XCTAssertEqual(try requestJSON(capturedRequests[1])["status"] as? String, "open")
        XCTAssertEqual(cancelled?.status, "cancelled")
        XCTAssertEqual(reopened?.status, "open")
    }

    @MainActor
    func testDeleteTaskRequiresOwnedRowAndOnlySucceedsWhenServerReturnsIt() async throws {
        var capturedRequest: URLRequest?
        HubTaskURLProtocol.handler = { request in
            capturedRequest = request
            return Self.response(
                for: request,
                body: """
                [{"id":"11111111-1111-4111-8111-111111111111","author_id":"f3eea23f-0aeb-405b-ab35-2c53173b7a8f","title":"Task","status":"cancelled"}]
                """
            )
        }
        let service = makeService()

        let deleted = await service.deleteTask(
            taskId: taskID,
            authorId: ownerID,
            accessToken: "owner-token"
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        assertOwnedRowScope(request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=representation")
        XCTAssertTrue(deleted)

        HubTaskURLProtocol.handler = { request in
            Self.response(for: request, body: "[]")
        }
        let denied = await service.deleteTask(
            taskId: taskID,
            authorId: ownerID,
            accessToken: "owner-token"
        )
        XCTAssertFalse(denied)
    }

    @MainActor
    private func makeService() -> HubService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HubTaskURLProtocol.self]
        return HubService(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://example.test")!,
            anonKey: "anon-key"
        )
    }

    private func assertOwnerScope(
        _ request: URLRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer owner-token",
            file: file,
            line: line
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "apikey"),
            "anon-key",
            file: file,
            line: line
        )
        XCTAssertEqual(
            queryValue("author_id", in: request),
            "eq.\(ownerID)",
            file: file,
            line: line
        )
    }

    private func assertOwnedRowScope(
        _ request: URLRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOwnerScope(request, file: file, line: line)
        XCTAssertEqual(
            queryValue("id", in: request),
            "eq.\(taskID)",
            file: file,
            line: line
        )
    }

    private func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class HubTaskURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
