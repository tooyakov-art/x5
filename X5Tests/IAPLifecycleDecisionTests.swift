import Foundation
import XCTest
@testable import X5

final class IAPLifecycleDecisionTests: XCTestCase {
    func testAppliedEntitlementFinishesTransactionAndReportsPurchaseSuccess() {
        let disposition = IAPEntitlementDisposition.applied

        XCTAssertTrue(disposition.shouldFinishTransaction)
        XCTAssertTrue(disposition.isPurchaseSuccess)
    }

    func testSkippedEntitlementFinishesTransactionWithoutReportingPurchaseSuccess() {
        let disposition = IAPEntitlementDisposition.skipped

        XCTAssertTrue(disposition.shouldFinishTransaction)
        XCTAssertFalse(disposition.isPurchaseSuccess)
    }

    func testFailedEntitlementRemainsPendingAndDoesNotReportPurchaseSuccess() {
        let disposition = IAPEntitlementDisposition.failed

        XCTAssertFalse(disposition.shouldFinishTransaction)
        XCTAssertFalse(disposition.isPurchaseSuccess)
    }

    func testUnauthorizedVerificationRetriesExactlyOnce() {
        XCTAssertTrue(IAPVerificationRetryPolicy.shouldRetry(statusCode: 401, retryCount: 0))
        XCTAssertFalse(IAPVerificationRetryPolicy.shouldRetry(statusCode: 401, retryCount: 1))
    }

    func testNonAuthorizationFailureDoesNotRefreshToken() {
        XCTAssertFalse(IAPVerificationRetryPolicy.shouldRetry(statusCode: 500, retryCount: 0))
    }

    func testMismatchedLegacyTokenIsDeferredToServerOwnershipVerification() {
        let signedInUserID = "11111111-1111-4111-8111-111111111111"
        let historicalToken = UUID(uuidString: "22222222-2222-4222-8222-222222222222")

        XCTAssertTrue(
            IAPOwnershipRoutingPolicy.shouldVerifyOnServer(
                signedInUserID: signedInUserID,
                transactionAppAccountToken: historicalToken
            )
        )
    }

    func testOwnershipVerificationDoesNotStartWithoutSignedInUser() {
        XCTAssertFalse(
            IAPOwnershipRoutingPolicy.shouldVerifyOnServer(
                signedInUserID: nil,
                transactionAppAccountToken: nil
            )
        )
    }
}
