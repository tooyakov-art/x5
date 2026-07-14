import XCTest
@testable import X5

final class CoursePurchaseResponseTests: XCTestCase {
    func testDecodesPurchasedResponse() throws {
        let response = try decode(
            """
            {
              "status": "purchased",
              "course_id": "course-paid",
              "credits_remaining": 50000
            }
            """
        )

        XCTAssertEqual(response.status, .purchased)
        XCTAssertEqual(response.courseId, "course-paid")
        XCTAssertEqual(response.creditsRemaining, 50_000)
    }

    func testDecodesAlreadyOwnedResponse() throws {
        let response = try decode(
            """
            {
              "status": "already_owned",
              "course_id": "course-paid",
              "credits_remaining": 50000
            }
            """
        )

        XCTAssertEqual(response.status, .alreadyOwned)
        XCTAssertEqual(response.courseId, "course-paid")
        XCTAssertEqual(response.creditsRemaining, 50_000)
    }

    func testDecodesInsufficientCreditsResponse() throws {
        let response = try decode(
            """
            {
              "status": "insufficient_credits",
              "course_id": "course-paid",
              "credits_remaining": 10000
            }
            """
        )

        XCTAssertEqual(response.status, .insufficientCredits)
        XCTAssertEqual(response.courseId, "course-paid")
        XCTAssertEqual(response.creditsRemaining, 10_000)
    }

    private func decode(_ json: String) throws -> CoursePurchaseResponse {
        try JSONDecoder().decode(CoursePurchaseResponse.self, from: Data(json.utf8))
    }
}
