import XCTest
@testable import X5

final class CourseAccessPolicyTests: XCTestCase {
    func testFreeCourseHasFullAccess() {
        let course = makeCourse(id: "course-free", price: 50_000, isFree: true)

        XCTAssertTrue(CourseAccessPolicy.hasFullAccess(to: course, profile: makeProfile()))
    }

    func testZeroPriceCourseHasFullAccess() {
        let course = makeCourse(id: "course-zero", price: 0, isFree: false)

        XCTAssertTrue(CourseAccessPolicy.hasFullAccess(to: course, profile: makeProfile()))
    }

    func testMissingPriceUsesSameFreeSemanticsAsServer() {
        let course = makeCourse(id: "course-nil-price", price: nil, isFree: false)

        XCTAssertTrue(CourseAccessPolicy.hasFullAccess(to: course, profile: makeProfile()))
    }

    func testPurchasedCourseIdHasFullAccess() {
        let course = makeCourse(id: "course-paid", price: 50_000, isFree: false)
        let profile = makeProfile(purchasedCourseIds: ["course-paid"])

        XCTAssertTrue(CourseAccessPolicy.hasFullAccess(to: course, profile: profile))
    }

    func testProPlanAloneDoesNotUnlockPaidCourse() {
        let course = makeCourse(id: "course-paid", price: 50_000, isFree: false)
        let profile = makeProfile(plan: "pro")

        XCTAssertFalse(CourseAccessPolicy.hasFullAccess(to: course, profile: profile))
    }

    func testCourseAuthorHasFullAccess() {
        let course = makeCourse(
            id: "course-paid",
            price: 50_000,
            isFree: false,
            authorId: "user-1"
        )

        XCTAssertTrue(CourseAccessPolicy.hasFullAccess(to: course, profile: makeProfile()))
    }

    func testLegacyLessonPurchaseDoesNotBypassCourseGate() {
        let course = makeCourse(id: "course-paid", price: 50_000, isFree: false)
        let lesson = CourseLesson(
            id: "lesson-paid",
            title: "Paid",
            duration: nil,
            order: 1,
            price: 1,
            videoUrl: nil,
            youtubeUrl: nil,
            thumbnailUrl: nil,
            isFreePreview: false,
            sellSeparately: true
        )
        let profile = makeProfile(purchasedLessonIds: ["course-paid:lesson-paid"])

        XCTAssertFalse(CourseAccessPolicy.canAccess(lesson: lesson, in: course, profile: profile))
    }

    func testFreePreviewLessonIsAccessibleWhenCourseIsLocked() {
        let course = makeCourse(id: "course-paid", price: 50_000, isFree: false)
        let lesson = CourseLesson(
            id: "lesson-preview",
            title: "Preview",
            duration: nil,
            order: 1,
            price: nil,
            videoUrl: nil,
            youtubeUrl: nil,
            thumbnailUrl: nil,
            isFreePreview: true,
            sellSeparately: false
        )

        XCTAssertTrue(
            CourseAccessPolicy.canAccess(
                lesson: lesson,
                in: course,
                profile: makeProfile()
            )
        )
    }

    private func makeCourse(
        id: String,
        price: Int?,
        isFree: Bool,
        authorId: String? = nil
    ) -> Course {
        Course(
            id: id,
            title: "Course",
            description: nil,
            marketingHook: nil,
            coverUrl: nil,
            authorName: "DOPAMINE",
            authorId: authorId,
            price: price,
            isFree: isFree,
            isPublic: true,
            courseLanguage: "ru",
            averageRating: nil,
            studentsCount: nil,
            sortOrder: nil,
            categoriesRaw: []
        )
    }

    private func makeProfile(
        plan: String = "free",
        purchasedCourseIds: [String] = [],
        purchasedLessonIds: [String]? = nil
    ) -> UserProfile {
        UserProfile(
            id: "user-1",
            name: nil,
            nickname: nil,
            email: nil,
            avatar: nil,
            bio: nil,
            services: nil,
            plan: plan,
            credits: 100_000,
            purchasedCourseIds: purchasedCourseIds,
            purchasedLessonIds: purchasedLessonIds,
            subscriptionType: nil,
            subscriptionDate: nil,
            subscriptionEndDate: nil,
            socialLinks: nil,
            userRole: nil,
            specialistCategory: nil,
            showInHub: nil,
            isPublic: true,
            signupNumber: nil,
            language: "ru",
            lastSeen: nil,
            isVerified: nil,
            verifiedUntil: nil
        )
    }
}
