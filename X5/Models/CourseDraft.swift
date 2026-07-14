import Foundation

/// A lossless, editable representation of the nested `courses.categories` JSON.
///
/// Drafts keep server IDs stable and keep uploaded media URLs separate from local
/// replacement files. Selecting a replacement therefore cannot erase the media
/// that is currently saved on the server.
struct CourseDraft: Equatable {
    var categories: [CourseCategoryDraft]

    init(course: Course) {
        categories = course.categories.map { CourseCategoryDraft(category: $0) }
    }

    init(categories: [CourseCategoryDraft]) {
        self.categories = categories
    }

    var categoriesPayload: [[String: Any]] {
        categories
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { offset, category in
                category.payload(order: offset + 1)
            }
    }
}

struct CourseCategoryDraft: Identifiable, Equatable {
    var id: String
    var title: String
    var order: Int
    var icon: String?
    var days: [CourseDayDraft]

    init(id: String, title: String, order: Int, icon: String? = nil, days: [CourseDayDraft]) {
        self.id = id
        self.title = title
        self.order = order
        self.icon = icon
        self.days = days
    }

    init(category: CourseCategory) {
        id = category.id
        title = category.title
        order = category.order ?? 0
        icon = category.icon
        days = category.days.map { CourseDayDraft(day: $0) }
    }

    var orderedDays: [CourseDayDraft] {
        days.sorted { $0.order < $1.order }
    }

    static func defaultContent() -> CourseCategoryDraft {
        CourseCategoryDraft(
            id: "cat_\(UUID().uuidString)",
            title: "Основной раздел",
            order: 1,
            icon: "folder",
            days: [defaultDay(order: 1)]
        )
    }

    static func defaultDay(order: Int) -> CourseDayDraft {
        CourseDayDraft(
            id: "day_\(UUID().uuidString)",
            title: "День \(order)",
            order: order,
            lessons: []
        )
    }

    func payload(order: Int) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "title": title,
            "order": order,
            "days": orderedDays.enumerated().map { offset, day in
                day.payload(order: offset + 1)
            }
        ]
        if let icon = icon?.courseDraftTrimmed, !icon.isEmpty {
            result["icon"] = icon
        }
        return result
    }
}

struct CourseDayDraft: Identifiable, Equatable {
    var id: String
    var title: String
    var order: Int
    var lessons: [CourseLessonDraft]

    init(id: String, title: String, order: Int, lessons: [CourseLessonDraft]) {
        self.id = id
        self.title = title
        self.order = order
        self.lessons = lessons
    }

    init(day: CourseDay) {
        id = day.id
        title = day.title
        order = day.order ?? 0
        lessons = day.lessons.map { CourseLessonDraft(lesson: $0) }
    }

    var orderedLessons: [CourseLessonDraft] {
        lessons.sorted { $0.order < $1.order }
    }

    func payload(order: Int) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "order": order,
            "lessons": orderedLessons.enumerated().map { offset, lesson in
                lesson.payload(order: offset + 1)
            }
        ]
    }
}

struct CourseLessonDraft: Identifiable, Equatable {
    var id: String
    var title: String
    var duration: String
    var order: Int
    var price: String
    var savedVideoURL: String
    var youtubeURL: String
    var savedThumbnailURL: String
    var isFreePreview: Bool
    var sellSeparately: Bool
    var pendingVideoFileURL: URL?
    var pendingVideoFileName: String?
    var pendingThumbnailData: Data?

    /// Editing aliases keep URL text fields ergonomic while the saved/pending
    /// distinction remains explicit in the underlying draft model.
    var videoUrl: String {
        get { savedVideoURL }
        set { savedVideoURL = newValue }
    }

    var youtubeUrl: String {
        get { youtubeURL }
        set { youtubeURL = newValue }
    }

    var thumbnailUrl: String {
        get { savedThumbnailURL }
        set { savedThumbnailURL = newValue }
    }

    init(
        id: String,
        title: String,
        duration: String,
        order: Int,
        price: String,
        savedVideoURL: String,
        youtubeURL: String,
        savedThumbnailURL: String,
        isFreePreview: Bool,
        sellSeparately: Bool,
        pendingVideoFileURL: URL? = nil,
        pendingVideoFileName: String? = nil,
        pendingThumbnailData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.order = order
        self.price = price
        self.savedVideoURL = savedVideoURL
        self.youtubeURL = youtubeURL
        self.savedThumbnailURL = savedThumbnailURL
        self.isFreePreview = isFreePreview
        self.sellSeparately = sellSeparately
        self.pendingVideoFileURL = pendingVideoFileURL
        self.pendingVideoFileName = pendingVideoFileName
        self.pendingThumbnailData = pendingThumbnailData
    }

    init(
        id: String,
        title: String,
        duration: String,
        order: Int,
        price: String,
        videoUrl: String,
        youtubeUrl: String,
        thumbnailUrl: String,
        isFreePreview: Bool,
        sellSeparately: Bool,
        pendingVideoFileURL: URL? = nil,
        pendingVideoFileName: String? = nil,
        pendingThumbnailData: Data? = nil
    ) {
        self.init(
            id: id,
            title: title,
            duration: duration,
            order: order,
            price: price,
            savedVideoURL: videoUrl,
            youtubeURL: youtubeUrl,
            savedThumbnailURL: thumbnailUrl,
            isFreePreview: isFreePreview,
            sellSeparately: sellSeparately,
            pendingVideoFileURL: pendingVideoFileURL,
            pendingVideoFileName: pendingVideoFileName,
            pendingThumbnailData: pendingThumbnailData
        )
    }

    init(lesson: CourseLesson) {
        id = lesson.id
        title = lesson.title
        duration = lesson.duration ?? ""
        order = lesson.order ?? 0
        price = String(lesson.price ?? 0)
        savedVideoURL = lesson.videoUrl ?? ""
        youtubeURL = lesson.youtubeUrl ?? ""
        savedThumbnailURL = lesson.thumbnailUrl ?? ""
        isFreePreview = lesson.isFreePreview ?? false
        sellSeparately = lesson.sellSeparately ?? false
        pendingVideoFileURL = nil
        pendingVideoFileName = nil
        pendingThumbnailData = nil
    }

    static func new(order: Int) -> CourseLessonDraft {
        CourseLessonDraft(
            id: "lesson_\(UUID().uuidString)",
            title: "",
            duration: "",
            order: order,
            price: "0",
            savedVideoURL: "",
            youtubeURL: "",
            savedThumbnailURL: "",
            isFreePreview: false,
            sellSeparately: false
        )
    }

    var hasVideo: Bool {
        pendingVideoFileURL != nil
            || !savedVideoURL.courseDraftTrimmed.isEmpty
            || !youtubeURL.courseDraftTrimmed.isEmpty
    }

    var videoLabel: String {
        if let pendingVideoFileName = pendingVideoFileName?.courseDraftTrimmed,
           !pendingVideoFileName.isEmpty {
            return pendingVideoFileName
        }
        if !savedVideoURL.courseDraftTrimmed.isEmpty { return "Video URL" }
        if !youtubeURL.courseDraftTrimmed.isEmpty { return "YouTube" }
        return "Видео не задано"
    }

    mutating func stageVideoReplacement(fileURL: URL, fileName: String) {
        pendingVideoFileURL = fileURL
        pendingVideoFileName = fileName
    }

    mutating func markVideoUploadSucceeded(publicURL: String) {
        savedVideoURL = publicURL.courseDraftTrimmed
        pendingVideoFileURL = nil
        pendingVideoFileName = nil
    }

    mutating func stageThumbnailReplacement(jpegData: Data) {
        pendingThumbnailData = jpegData
    }

    mutating func markThumbnailUploadSucceeded(publicURL: String) {
        savedThumbnailURL = publicURL.courseDraftTrimmed
        pendingThumbnailData = nil
    }

    func payload(order: Int) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "title": title,
            "order": order,
            "price": Int(price) ?? 0,
            "isFreePreview": isFreePreview,
            "sellSeparately": sellSeparately
        ]
        if !duration.courseDraftTrimmed.isEmpty {
            result["duration"] = duration.courseDraftTrimmed
        }
        if !savedVideoURL.courseDraftTrimmed.isEmpty {
            result["videoUrl"] = savedVideoURL.courseDraftTrimmed
        }
        if !youtubeURL.courseDraftTrimmed.isEmpty {
            result["youtubeUrl"] = youtubeURL.courseDraftTrimmed
        }
        if !savedThumbnailURL.courseDraftTrimmed.isEmpty {
            result["thumbnailUrl"] = savedThumbnailURL.courseDraftTrimmed
        }
        return result
    }
}

/// Keeps a newly created hidden course row attached to the editor session so a
/// failed media upload or metadata PATCH can be retried without creating a
/// duplicate row.
struct CourseSaveIdentity: Equatable {
    private(set) var persistedCourseID: String?

    init(existingCourseID: String?) {
        persistedCourseID = existingCourseID
    }

    var requiresCourseCreation: Bool {
        persistedCourseID == nil
    }

    mutating func recordCreatedCourse(id: String) {
        guard persistedCourseID == nil else { return }
        persistedCourseID = id
    }
}

private extension String {
    var courseDraftTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
