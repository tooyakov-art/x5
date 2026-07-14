import Foundation

/// Centralizes course ownership rules so subscription state cannot
/// accidentally be treated as ownership of an independently priced course.
enum CourseAccessPolicy {
    static func hasFullAccess(to course: Course, profile: UserProfile?) -> Bool {
        if course.isFree == true { return true }
        if (course.price ?? 0) <= 0 { return true }
        if let authorId = course.authorId,
           profile?.id.caseInsensitiveCompare(authorId) == .orderedSame {
            return true
        }

        return profile?.purchasedCourseIds?.contains(course.id) == true
    }

    static func canAccess(
        lesson: CourseLesson,
        in course: Course,
        profile: UserProfile?
    ) -> Bool {
        if hasFullAccess(to: course, profile: profile) { return true }
        if lesson.freePreview { return true }
        return false
    }
}
