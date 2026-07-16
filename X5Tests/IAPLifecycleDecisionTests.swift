import Foundation
import XCTest
@testable import X5

final class IAPLifecycleDecisionTests: XCTestCase {
    @MainActor
    func testServerDeliveryFailureLeavesConsumableUnfinished() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        var verificationCalls = 0
        var finishCalls = 0

        let disposition = await lifecycle.deliver(
            transactionID: 101,
            authenticatedUserID: "11111111-1111-4111-8111-111111111111",
            verifyDelivery: {
                verificationCalls += 1
                return .failed
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(disposition, .failed)
        XCTAssertEqual(verificationCalls, 1)
        XCTAssertEqual(finishCalls, 0)
    }

    @MainActor
    func testRetryAfterServerAlreadyAppliedFinishesTransactionExactlyOnce() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        var verificationResults: [IAPEntitlementDisposition] = [.failed, .applied]
        var verificationCalls = 0
        var finishCalls = 0

        let firstAttempt = await lifecycle.deliver(
            transactionID: 202,
            authenticatedUserID: "11111111-1111-4111-8111-111111111111",
            verifyDelivery: {
                verificationCalls += 1
                return verificationResults.removeFirst()
            },
            finish: { finishCalls += 1 }
        )
        let retryAfterAlreadyApplied = await lifecycle.deliver(
            transactionID: 202,
            authenticatedUserID: "11111111-1111-4111-8111-111111111111",
            verifyDelivery: {
                verificationCalls += 1
                // `.applied` is the client disposition for both the server's
                // `applied` and exact-once `already_applied` responses.
                return verificationResults.removeFirst()
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(firstAttempt, .failed)
        XCTAssertEqual(retryAfterAlreadyApplied, .applied)
        XCTAssertEqual(verificationCalls, 2)
        XCTAssertEqual(finishCalls, 1)
    }

    @MainActor
    func testDuplicateDeliveryDoesNotVerifyOrFinishTransactionTwice() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        let accountID = "11111111-1111-4111-8111-111111111111"
        var verificationCalls = 0
        var finishCalls = 0

        let firstDelivery = await lifecycle.deliver(
            transactionID: 303,
            authenticatedUserID: accountID,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )
        let duplicateDelivery = await lifecycle.deliver(
            transactionID: 303,
            authenticatedUserID: accountID,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(firstDelivery, .applied)
        XCTAssertEqual(duplicateDelivery, .applied)
        XCTAssertEqual(verificationCalls, 1)
        XCTAssertEqual(finishCalls, 1)
    }

    @MainActor
    func testAppliedTransactionIsReverifiedWhenAuthenticatedAccountChanges() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        let accountA = "11111111-1111-4111-8111-111111111111"
        let accountB = "22222222-2222-4222-8222-222222222222"
        var verificationCalls = 0
        var finishCalls = 0

        let firstAccount = await lifecycle.deliver(
            transactionID: 353,
            authenticatedUserID: accountA,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )
        let secondAccount = await lifecycle.deliver(
            transactionID: 353,
            authenticatedUserID: accountB,
            verifyDelivery: {
                verificationCalls += 1
                // The server maps a restorable entitlement owned by account A
                // to `.skipped` when account B attempts to claim it.
                return .skipped
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(firstAccount, .applied)
        XCTAssertEqual(secondAccount, .skipped)
        XCTAssertFalse(secondAccount.isPurchaseSuccess)
        XCTAssertEqual(verificationCalls, 2)
        XCTAssertEqual(finishCalls, 2)
    }

    @MainActor
    func testRejectedCrossAccountConsumableRemainsUnfinished() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        let accountA = "11111111-1111-4111-8111-111111111111"
        let accountB = "22222222-2222-4222-8222-222222222222"
        var verificationCalls = 0
        var finishCalls = 0

        _ = await lifecycle.deliver(
            transactionID: 363,
            authenticatedUserID: accountA,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )
        let secondAccount = await lifecycle.deliver(
            transactionID: 363,
            authenticatedUserID: accountB,
            verifyDelivery: {
                verificationCalls += 1
                // Consumable ownership rejection maps to `.failed`, keeping
                // StoreKit delivery retryable for the owning X5 account.
                return .failed
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(secondAccount, .failed)
        XCTAssertFalse(secondAccount.isPurchaseSuccess)
        XCTAssertEqual(verificationCalls, 2)
        XCTAssertEqual(finishCalls, 1)
    }

    @MainActor
    func testSkippedOwnershipCanBeVerifiedAgainAfterAccountChanges() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        let otherAccountID = "11111111-1111-4111-8111-111111111111"
        let ownerAccountID = "22222222-2222-4222-8222-222222222222"
        var verificationResults: [IAPEntitlementDisposition] = [.skipped, .applied]
        var verificationCalls = 0
        var finishCalls = 0

        let otherAccount = await lifecycle.deliver(
            transactionID: 404,
            authenticatedUserID: otherAccountID,
            verifyDelivery: {
                verificationCalls += 1
                return verificationResults.removeFirst()
            },
            finish: { finishCalls += 1 }
        )
        let owningAccount = await lifecycle.deliver(
            transactionID: 404,
            authenticatedUserID: ownerAccountID,
            verifyDelivery: {
                verificationCalls += 1
                return verificationResults.removeFirst()
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(otherAccount, .skipped)
        XCTAssertEqual(owningAccount, .applied)
        XCTAssertEqual(verificationCalls, 2)
        XCTAssertEqual(finishCalls, 2)
    }

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

    func testVerifiedPurchaseIsRecordedInActiveSubscriptionSnapshotImmediately() {
        let initial = IAPActiveSubscriptionSnapshot(productIDs: [String]())

        let updated = initial.recordingActivePurchase(
            productID: IAPService.verifiedMonthlyProductID
        )

        XCTAssertTrue(updated.hasActiveVerifiedSubscription)
        XCTAssertTrue(updated.hasAnyActiveSubscription)
    }

    func testFailedProfileReloadUsesPendingRefreshConfirmation() {
        XCTAssertEqual(
            IAPCreditPurchaseConfirmation.messageKey(profileReloadSucceeded: false),
            "credit_store_success_refresh_pending"
        )
        XCTAssertEqual(
            IAPCreditPurchaseConfirmation.messageKey(profileReloadSucceeded: true),
            "credit_store_success_message"
        )
    }

    @MainActor
    func testRevocationReverifiesACompletedTransactionExactlyOnce() async {
        let lifecycle = IAPTransactionLifecycleCoordinator()
        let accountID = "11111111-1111-4111-8111-111111111111"
        let revokedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var verificationCalls = 0
        var finishCalls = 0

        _ = await lifecycle.deliver(
            transactionID: 505,
            authenticatedUserID: accountID,
            revocationDate: nil,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )
        _ = await lifecycle.deliver(
            transactionID: 505,
            authenticatedUserID: accountID,
            revocationDate: revokedAt,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )
        _ = await lifecycle.deliver(
            transactionID: 505,
            authenticatedUserID: accountID,
            revocationDate: revokedAt,
            verifyDelivery: {
                verificationCalls += 1
                return .applied
            },
            finish: { finishCalls += 1 }
        )

        XCTAssertEqual(verificationCalls, 2)
        XCTAssertEqual(finishCalls, 2)
    }
}
