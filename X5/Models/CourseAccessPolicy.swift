import Foundation

/// Centralizes course ownership rules so subscription state cannot
/// accidentally be treated as ownership of an independently priced course.
enum CourseAccessPolicy {
    static func hasFullAccess(to course: Course, profile: UserProfile?) -> Bool {
        if course.isFree == true { return true }
        if let price = course.price, price <= 0 { return true }

        return profile?.purchasedCourseIds?.contains(course.id) == true
    }

    static func canAccess(
        lesson: CourseLesson,
        in course: Course,
        profile: UserProfile?
    ) -> Bool {
        if hasFullAccess(to: course, profile: profile) { return true }
        if lesson.freePreview { return true }

        let purchaseKey = "\(course.id):\(lesson.id)"
        return profile?.purchasedLessonIds?.contains(purchaseKey) == true
    }
}
