import XCTest
@testable import X5

final class UserProfileEntitlementTests: XCTestCase {
    func testActivePaidTiersUseServerExpirationDate() {
        XCTAssertTrue(makeProfile(plan: "lite", endDate: "2099-01-01T00:00:00Z").isPro)
        XCTAssertTrue(makeProfile(plan: "pro", endDate: "2099-01-01T00:00:00.000Z").isPro)
        XCTAssertTrue(makeProfile(plan: "max", endDate: "2099-01-01T00:00:00Z").isPro)
        XCTAssertFalse(makeProfile(plan: "max", endDate: "2000-01-01T00:00:00Z").isPro)
    }

    func testLegacyPaidProfileWithoutExpirationKeepsAccess() {
        XCTAssertTrue(makeProfile(plan: "pro", endDate: nil).isPro)
    }

    func testMalformedExpirationFailsClosedForTrackedSubscription() {
        XCTAssertFalse(makeProfile(plan: "pro", endDate: "not-a-date").isPro)
    }

    func testBlackRemainsLifetimeAndFreeRemainsLocked() {
        XCTAssertTrue(makeProfile(plan: "black", endDate: "2000-01-01T00:00:00Z").isPro)
        XCTAssertFalse(makeProfile(plan: "free", endDate: "2099-01-01T00:00:00Z").isPro)
    }

    private func makeProfile(plan: String, endDate: String?) -> UserProfile {
        UserProfile(
            id: "entitlement-test-user",
            name: nil,
            nickname: nil,
            email: nil,
            avatar: nil,
            bio: nil,
            services: nil,
            plan: plan,
            credits: 0,
            purchasedCourseIds: nil,
            purchasedLessonIds: nil,
            subscriptionType: nil,
            subscriptionDate: nil,
            subscriptionEndDate: endDate,
            socialLinks: nil,
            userRole: nil,
            specialistCategory: nil,
            showInHub: nil,
            isPublic: nil,
            signupNumber: nil,
            language: nil,
            lastSeen: nil,
            isVerified: nil,
            verifiedUntil: nil
        )
    }
}
