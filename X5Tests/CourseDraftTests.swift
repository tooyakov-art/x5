import XCTest
@testable import X5

final class CourseDraftTests: XCTestCase {
    func testRoundTripPreservesModulesStableIDsSiblingLessonsAndVideoURL() throws {
        let original = makeCourse()

        let payload = CourseDraft(course: original).categoriesPayload

        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload[0]["id"] as? String, "module-1")
        XCTAssertEqual(payload[1]["id"] as? String, "module-2")

        let firstModuleDays = try XCTUnwrap(payload[0]["days"] as? [[String: Any]])
        XCTAssertEqual(firstModuleDays.first?["id"] as? String, "day-1")

        let siblingLessons = try XCTUnwrap(firstModuleDays.first?["lessons"] as? [[String: Any]])
        XCTAssertEqual(siblingLessons.map { $0["id"] as? String }, ["lesson-1", "lesson-2"])
        XCTAssertEqual(siblingLessons[0]["videoUrl"] as? String, "https://cdn.example.com/lesson-1.mp4")
        XCTAssertEqual(siblingLessons[1]["videoUrl"] as? String, "https://cdn.example.com/lesson-2.mp4")

        let secondModuleDays = try XCTUnwrap(payload[1]["days"] as? [[String: Any]])
        let secondModuleLessons = try XCTUnwrap(secondModuleDays.first?["lessons"] as? [[String: Any]])
        XCTAssertEqual(secondModuleDays.first?["id"] as? String, "day-2")
        XCTAssertEqual(secondModuleLessons.first?["id"] as? String, "lesson-3")
    }

    func testStagedReplacementKeepsSavedVideoUntilUploadSucceeds() {
        var draft = CourseLessonDraft(lesson: makeLesson(
            id: "lesson-1",
            order: 1,
            videoURL: "https://cdn.example.com/original.mp4"
        ))
        let replacement = URL(fileURLWithPath: "/tmp/replacement.mp4")

        draft.stageVideoReplacement(fileURL: replacement, fileName: "replacement.mp4")

        XCTAssertEqual(draft.savedVideoURL, "https://cdn.example.com/original.mp4")
        XCTAssertEqual(draft.pendingVideoFileURL, replacement)
        XCTAssertEqual(draft.payload(order: 1)["videoUrl"] as? String, "https://cdn.example.com/original.mp4")

        draft.markVideoUploadSucceeded(publicURL: "https://cdn.example.com/replacement.mp4")

        XCTAssertEqual(draft.savedVideoURL, "https://cdn.example.com/replacement.mp4")
        XCTAssertNil(draft.pendingVideoFileURL)
        XCTAssertNil(draft.pendingVideoFileName)
        XCTAssertEqual(draft.payload(order: 1)["videoUrl"] as? String, "https://cdn.example.com/replacement.mp4")
    }

    func testSaveIdentityReusesCreatedCourseIDForRetry() {
        var identity = CourseSaveIdentity(existingCourseID: nil)

        XCTAssertTrue(identity.requiresCourseCreation)
        identity.recordCreatedCourse(id: "created-course-id")

        XCTAssertFalse(identity.requiresCourseCreation)
        XCTAssertEqual(identity.persistedCourseID, "created-course-id")

        identity.recordCreatedCourse(id: "duplicate-course-id")
        XCTAssertEqual(identity.persistedCourseID, "created-course-id")
    }

    private func makeCourse() -> Course {
        Course(
            id: "course-1",
            title: "Targeting",
            description: nil,
            marketingHook: nil,
            coverUrl: nil,
            authorName: "DOPAMINE",
            price: 50_000,
            isFree: false,
            isPublic: true,
            courseLanguage: "ru",
            averageRating: nil,
            studentsCount: nil,
            sortOrder: 1,
            categoriesRaw: [
                CourseCategory(
                    id: "module-1",
                    title: "Module 1",
                    order: 1,
                    icon: "folder",
                    days: [CourseDay(
                        id: "day-1",
                        title: "Day 1",
                        order: 1,
                        lessons: [
                            makeLesson(id: "lesson-1", order: 1, videoURL: "https://cdn.example.com/lesson-1.mp4"),
                            makeLesson(id: "lesson-2", order: 2, videoURL: "https://cdn.example.com/lesson-2.mp4")
                        ]
                    )]
                ),
                CourseCategory(
                    id: "module-2",
                    title: "Module 2",
                    order: 2,
                    icon: nil,
                    days: [CourseDay(
                        id: "day-2",
                        title: "Day 2",
                        order: 1,
                        lessons: [makeLesson(id: "lesson-3", order: 1, videoURL: nil)]
                    )]
                )
            ]
        )
    }

    private func makeLesson(id: String, order: Int, videoURL: String?) -> CourseLesson {
        CourseLesson(
            id: id,
            title: "Lesson \(order)",
            duration: "10:00",
            order: order,
            price: 0,
            videoUrl: videoURL,
            youtubeUrl: nil,
            thumbnailUrl: nil,
            isFreePreview: false,
            sellSeparately: false
        )
    }
}
