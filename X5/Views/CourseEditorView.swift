import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Developer-only course editor. Handles course metadata, cover image, and lessons
/// stored inside `courses.categories` JSON.
struct CourseEditorView: View {
    @EnvironmentObject private var auth: Auth
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CoursesService()

    /// Pass an existing course to edit it. Pass nil to create a new one.
    let editing: Course?
    var onChange: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var marketingHook: String = ""
    @State private var price: String = "0"
    @State private var isFree: Bool = true
    @State private var isPublic: Bool = false
    @State private var courseLanguage: String = "ru"
    @State private var coverUrl: String?
    @State private var categories: [EditableCategory] = [.defaultContent()]

    @State private var coverItem: PhotosPickerItem?
    @State private var coverPreviewData: Data?
    @State private var uploadingCover = false

    @State private var lessonEditor: LessonEditorTarget?
    @State private var didPopulate = false
    @State private var saving = false
    @State private var deleteConfirm = false
    @State private var errorText: String?

    private var isCreating: Bool { editing == nil }
    private var existingId: String? { editing?.id }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    coverPicker
                }

                Section("Основное") {
                    TextField("Название курса", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Подзаголовок", text: $marketingHook)
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Цена и доступ") {
                    Toggle("Бесплатный", isOn: $isFree)
                    if !isFree {
                        HStack {
                            Text("Цена, $")
                            Spacer()
                            TextField("0", text: $price)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                    Toggle("Опубликован", isOn: $isPublic)
                }

                Section("Язык") {
                    Picker("Язык курса", selection: $courseLanguage) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                        Text("Қазақша").tag("kk")
                    }
                }

                lessonsSection

                if !isCreating {
                    Section {
                        Button(role: .destructive) {
                            deleteConfirm = true
                        } label: {
                            Label("Удалить курс", systemImage: "trash")
                        }
                    } footer: {
                        Text("Удаление необратимо.")
                    }
                }

                if let err = errorText {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle(isCreating ? "Новый курс" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Сохранить").bold() }
                    }
                    .disabled(saving || title.x5Trimmed.isEmpty)
                }
            }
            .confirmationDialog("Удалить курс?", isPresented: $deleteConfirm, titleVisibility: .visible) {
                Button("Удалить навсегда", role: .destructive) {
                    Task { await runDelete() }
                }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(item: $lessonEditor) { target in
                LessonEditorSheet(
                    lesson: target.lesson,
                    uploadBlockerText: videoUploadBlockerText,
                    uploadsImmediately: existingId != nil,
                    uploadVideo: { fileURL in
                        await uploadVideo(fileURL, lessonId: target.lesson.id)
                    },
                    uploadThumbnail: { jpegData in
                        await uploadThumbnail(jpegData, lessonId: target.lesson.id)
                    },
                    onSave: { saved in
                        upsertLesson(saved, categoryId: target.categoryId, dayId: target.dayId)
                    }
                )
            }
            .onAppear { populate() }
            .onChange(of: coverItem) { newValue in
                guard let newValue else { return }
                Task { await loadCoverPreview(newValue) }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var coverPicker: some View {
        PhotosPicker(selection: $coverItem, matching: .images) {
            ZStack {
                if let data = coverPreviewData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if let url = coverUrl, !url.isEmpty, let u = URL(string: url) {
                    CachedAsyncImage(url: u) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
                if uploadingCover {
                    Color.black.opacity(0.4)
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
            Text("Обложка")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    private var lessonsSection: some View {
        Section {
            ForEach(orderedCategoryIndices, id: \.self) { categoryIndex in
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Название раздела", text: $categories[categoryIndex].title)
                        .font(.headline)
                        .textInputAutocapitalization(.sentences)

                    TextField("Иконка SF Symbol, например folder", text: iconBinding(for: categoryIndex))
                        .font(.caption)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    ForEach(orderedDayIndices(in: categoryIndex), id: \.self) { dayIndex in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Название дня или модуля", text: $categories[categoryIndex].days[dayIndex].title)
                                    .font(.subheadline)
                                    .textInputAutocapitalization(.sentences)

                                if categories[categoryIndex].days.count > 1 {
                                    Button(role: .destructive) {
                                        deleteDay(categoryIndex: categoryIndex, dayIndex: dayIndex)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            if categories[categoryIndex].days[dayIndex].lessons.isEmpty {
                                Text("Уроков пока нет")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(categories[categoryIndex].days[dayIndex].orderedLessons) { lesson in
                                Button {
                                    lessonEditor = LessonEditorTarget(
                                        categoryId: categories[categoryIndex].id,
                                        dayId: categories[categoryIndex].days[dayIndex].id,
                                        lesson: lesson
                                    )
                                } label: {
                                    LessonDraftRow(lesson: lesson)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteLesson(lesson.id, categoryIndex: categoryIndex, dayIndex: dayIndex)
                                    } label: {
                                        Label("Удалить урок", systemImage: "trash")
                                    }
                                }
                            }

                            Button {
                                openNewLesson(
                                    categoryId: categories[categoryIndex].id,
                                    dayId: categories[categoryIndex].days[dayIndex].id
                                )
                            } label: {
                                Label("Добавить урок", systemImage: "plus.circle")
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                    }

                    HStack {
                        Button {
                            addDay(categoryIndex: categoryIndex)
                        } label: {
                            Label("Добавить день / модуль", systemImage: "calendar.badge.plus")
                        }

                        Spacer()

                        if categories.count > 1 {
                            Button(role: .destructive) {
                                deleteCategory(categoryIndex)
                            } label: {
                                Label("Удалить раздел", systemImage: "trash")
                            }
                        }
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 6)
            }

            Button {
                addCategory()
            } label: {
                Label("Добавить раздел", systemImage: "folder.badge.plus")
            }
        } header: {
            Text("Программа курса")
        } footer: {
            Text("Можно менять названия разделов и дней, добавлять модули и уроки. Видео у урока задается прямой ссылкой MP4/HLS или импортом файла.")
        }
    }

    private var videoUploadBlockerText: String? {
        if auth.accessToken == nil {
            return "Для загрузки файла нужен активный вход разработчика."
        }
        return nil
    }

    private func populate() {
        guard !didPopulate else { return }
        didPopulate = true

        guard let c = editing else {
            categories = [.defaultContent()]
            return
        }
        title = c.title
        description = c.description ?? ""
        marketingHook = c.marketingHook ?? ""
        price = String(c.price ?? 0)
        isFree = c.isFree ?? false
        isPublic = c.isPublic ?? false
        courseLanguage = c.courseLanguage ?? "ru"
        coverUrl = c.coverUrl
        categories = c.categories.map(EditableCategory.init)
        if categories.isEmpty {
            categories = [.defaultContent()]
        }
    }

    private func loadCoverPreview(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data),
           let jpeg = ui.jpegData(compressionQuality: 0.85) {
            coverPreviewData = jpeg
        }
    }

    private func save() async {
        guard let token = await auth.freshAccessToken() else { return }
        saving = true
        defer { saving = false }
        errorText = nil

        var courseId = existingId

        // Create row first if new. This gives storage a stable course path.
        if courseId == nil {
            guard let created = await service.createCourse(title: title, accessToken: token) else {
                errorText = service.error ?? "Не удалось создать курс."
                return
            }
            courseId = created.id
        }
        guard let id = courseId else { return }

        if let jpeg = coverPreviewData {
            uploadingCover = true
            _ = await service.uploadCover(courseId: id, jpegData: jpeg, accessToken: token)
            uploadingCover = false
        }

        guard await uploadPendingLessonVideos(courseId: id, accessToken: token) else {
            return
        }
        guard await uploadPendingLessonThumbnails(courseId: id, accessToken: token) else {
            return
        }

        let priceInt = Int(price) ?? 0
        let fields: [String: Any] = [
            "title": title,
            "description": description.x5Trimmed.isEmpty ? NSNull() : description,
            "marketing_hook": marketingHook.x5Trimmed.isEmpty ? NSNull() : marketingHook,
            "price": priceInt,
            "is_free": isFree,
            "is_public": isPublic,
            "course_language": courseLanguage,
            "categories": categoriesPayload()
        ]
        let ok = await service.updateCourse(id: id, fields: fields, accessToken: token)
        if !ok {
            errorText = service.error ?? "Не удалось сохранить."
            return
        }
        onChange()
        dismiss()
    }

    private func runDelete() async {
        guard let id = existingId, let token = await auth.freshAccessToken() else { return }
        saving = true
        defer { saving = false }
        let ok = await service.deleteCourse(id: id, accessToken: token)
        if ok {
            onChange()
            dismiss()
        } else {
            errorText = service.error ?? "Не удалось удалить."
        }
    }

    private func uploadVideo(_ fileURL: URL, lessonId: String) async -> LessonVideoUploadResult {
        guard let courseId = existingId else {
            return .failure("Сначала сохраните курс как черновик, затем откройте редактирование и загрузите файл.")
        }
        guard let token = await auth.freshAccessToken() else {
            return .failure("Нужен активный вход разработчика.")
        }
        if let publicURL = await service.uploadLessonVideo(courseId: courseId, lessonId: lessonId, fileURL: fileURL, accessToken: token) {
            return .success(publicURL)
        }
        return .failure(service.error ?? "Не удалось загрузить видео.")
    }

    private func uploadThumbnail(_ jpegData: Data, lessonId: String) async -> LessonThumbnailUploadResult {
        guard let courseId = existingId else {
            return .failure("Сначала сохраните курс как черновик, затем откройте редактирование и загрузите обложку.")
        }
        guard let token = await auth.freshAccessToken() else {
            return .failure("Нужен активный вход разработчика.")
        }
        if let publicURL = await service.uploadLessonThumbnail(courseId: courseId, lessonId: lessonId, jpegData: jpegData, accessToken: token) {
            return .success(publicURL)
        }
        return .failure(service.error ?? "Не удалось загрузить обложку урока.")
    }

    private func uploadPendingLessonVideos(courseId: String, accessToken: String) async -> Bool {
        for categoryIndex in categories.indices {
            for dayIndex in categories[categoryIndex].days.indices {
                for lessonIndex in categories[categoryIndex].days[dayIndex].lessons.indices {
                    guard let fileURL = categories[categoryIndex].days[dayIndex].lessons[lessonIndex].pendingVideoFileURL else {
                        continue
                    }

                    let lessonId = categories[categoryIndex].days[dayIndex].lessons[lessonIndex].id
                    guard let publicURL = await service.uploadLessonVideo(courseId: courseId, lessonId: lessonId, fileURL: fileURL, accessToken: accessToken) else {
                        errorText = service.error ?? "Не удалось загрузить видео урока."
                        return false
                    }

                    categories[categoryIndex].days[dayIndex].lessons[lessonIndex].videoUrl = publicURL
                    categories[categoryIndex].days[dayIndex].lessons[lessonIndex].pendingVideoFileURL = nil
                    categories[categoryIndex].days[dayIndex].lessons[lessonIndex].pendingVideoFileName = nil
                }
            }
        }
        return true
    }

    private func uploadPendingLessonThumbnails(courseId: String, accessToken: String) async -> Bool {
        for categoryIndex in categories.indices {
            for dayIndex in categories[categoryIndex].days.indices {
                for lessonIndex in categories[categoryIndex].days[dayIndex].lessons.indices {
                    guard let jpegData = categories[categoryIndex].days[dayIndex].lessons[lessonIndex].pendingThumbnailData else {
                        continue
                    }

                    let lessonId = categories[categoryIndex].days[dayIndex].lessons[lessonIndex].id
                    guard let publicURL = await service.uploadLessonThumbnail(courseId: courseId, lessonId: lessonId, jpegData: jpegData, accessToken: accessToken) else {
                        errorText = service.error ?? "Не удалось загрузить обложку урока."
                        return false
                    }

                    categories[categoryIndex].days[dayIndex].lessons[lessonIndex].thumbnailUrl = publicURL
                    categories[categoryIndex].days[dayIndex].lessons[lessonIndex].pendingThumbnailData = nil
                }
            }
        }
        return true
    }


    private func orderedCategories() -> [EditableCategory] {
        categories.sorted { $0.order < $1.order }
    }

    private var orderedCategoryIndices: [Int] {
        categories.indices.sorted { categories[$0].order < categories[$1].order }
    }

    private func orderedDayIndices(in categoryIndex: Int) -> [Int] {
        guard categories.indices.contains(categoryIndex) else { return [] }
        return categories[categoryIndex].days.indices.sorted {
            categories[categoryIndex].days[$0].order < categories[categoryIndex].days[$1].order
        }
    }

    private func iconBinding(for categoryIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard categories.indices.contains(categoryIndex) else { return "" }
                return categories[categoryIndex].icon ?? ""
            },
            set: { value in
                guard categories.indices.contains(categoryIndex) else { return }
                categories[categoryIndex].icon = value.x5Trimmed.isEmpty ? nil : value.x5Trimmed
            }
        )
    }

    private func categoriesPayload() -> [[String: Any]] {
        orderedCategories().enumerated().map { index, category in
            category.payload(order: index + 1)
        }
    }

    private func ensureDefaultContent() {
        if categories.isEmpty {
            categories = [.defaultContent()]
        }
        for index in categories.indices where categories[index].days.isEmpty {
            categories[index].days = [EditableCategory.defaultDay(order: 1)]
        }
    }

    private func addCategory() {
        let nextOrder = (categories.map(\.order).max() ?? 0) + 1
        categories.append(
            EditableCategory(
                id: "cat_\(UUID().uuidString)",
                title: "Новый раздел",
                order: nextOrder,
                icon: "folder",
                days: [EditableCategory.defaultDay(order: 1)]
            )
        )
    }

    private func deleteCategory(_ categoryIndex: Int) {
        guard categories.indices.contains(categoryIndex), categories.count > 1 else { return }
        categories.remove(at: categoryIndex)
        normalizeCategoryOrder()
    }

    private func addDay(categoryIndex: Int) {
        guard categories.indices.contains(categoryIndex) else { return }
        let nextOrder = (categories[categoryIndex].days.map(\.order).max() ?? 0) + 1
        categories[categoryIndex].days.append(EditableCategory.defaultDay(order: nextOrder))
    }

    private func deleteDay(categoryIndex: Int, dayIndex: Int) {
        guard categories.indices.contains(categoryIndex),
              categories[categoryIndex].days.indices.contains(dayIndex),
              categories[categoryIndex].days.count > 1 else { return }
        categories[categoryIndex].days.remove(at: dayIndex)
        normalizeDayOrder(categoryIndex: categoryIndex)
    }

    private func deleteLesson(_ lessonId: String, categoryIndex: Int, dayIndex: Int) {
        guard categories.indices.contains(categoryIndex),
              categories[categoryIndex].days.indices.contains(dayIndex) else { return }
        categories[categoryIndex].days[dayIndex].lessons.removeAll { $0.id == lessonId }
        normalizeLessonOrder(categoryIndex: categoryIndex, dayIndex: dayIndex)
    }

    private func normalizeCategoryOrder() {
        for (offset, categoryIndex) in orderedCategoryIndices.enumerated() {
            categories[categoryIndex].order = offset + 1
        }
    }

    private func normalizeDayOrder(categoryIndex: Int) {
        guard categories.indices.contains(categoryIndex) else { return }
        for (offset, dayIndex) in orderedDayIndices(in: categoryIndex).enumerated() {
            categories[categoryIndex].days[dayIndex].order = offset + 1
        }
    }

    private func openFirstNewLesson() {
        ensureDefaultContent()
        guard let category = orderedCategories().first,
              let day = category.orderedDays.first else { return }
        openNewLesson(categoryId: category.id, dayId: day.id)
    }

    private func openNewLesson(categoryId: String, dayId: String) {
        let nextOrder = lessons(categoryId: categoryId, dayId: dayId).count + 1
        lessonEditor = LessonEditorTarget(categoryId: categoryId, dayId: dayId, lesson: .new(order: nextOrder))
    }

    private func lessons(categoryId: String, dayId: String) -> [EditableLesson] {
        guard let category = categories.first(where: { $0.id == categoryId }),
              let day = category.days.first(where: { $0.id == dayId }) else { return [] }
        return day.lessons
    }

    private func upsertLesson(_ lesson: EditableLesson, categoryId: String, dayId: String) {
        guard let categoryIndex = categories.firstIndex(where: { $0.id == categoryId }),
              let dayIndex = categories[categoryIndex].days.firstIndex(where: { $0.id == dayId }) else { return }

        if let lessonIndex = categories[categoryIndex].days[dayIndex].lessons.firstIndex(where: { $0.id == lesson.id }) {
            categories[categoryIndex].days[dayIndex].lessons[lessonIndex] = lesson
        } else {
            categories[categoryIndex].days[dayIndex].lessons.append(lesson)
        }
        normalizeLessonOrder(categoryIndex: categoryIndex, dayIndex: dayIndex)
    }

    private func normalizeLessonOrder(categoryIndex: Int, dayIndex: Int) {
        let sorted = categories[categoryIndex].days[dayIndex].orderedLessons.enumerated().map { index, lesson in
            var updated = lesson
            updated.order = index + 1
            return updated
        }
        categories[categoryIndex].days[dayIndex].lessons = sorted
    }
}

private struct LessonEditorTarget: Identifiable {
    let categoryId: String
    let dayId: String
    let lesson: EditableLesson

    var id: String { "\(categoryId)-\(dayId)-\(lesson.id)" }
}

private struct EditableCategory: Identifiable, Equatable {
    var id: String
    var title: String
    var order: Int
    var icon: String?
    var days: [EditableDay]

    init(id: String, title: String, order: Int, icon: String? = nil, days: [EditableDay]) {
        self.id = id
        self.title = title
        self.order = order
        self.icon = icon
        self.days = days
    }

    init(_ category: CourseCategory) {
        self.id = category.id
        self.title = category.title
        self.order = category.order ?? 0
        self.icon = category.icon
        self.days = category.days.map(EditableDay.init)
    }

    var orderedDays: [EditableDay] {
        days.sorted { $0.order < $1.order }
    }

    static func defaultContent() -> EditableCategory {
        EditableCategory(id: "cat_\(UUID().uuidString)", title: "Основной раздел", order: 1, icon: "folder", days: [Self.defaultDay(order: 1)])
    }

    static func defaultDay(order: Int) -> EditableDay {
        EditableDay(id: "day_\(UUID().uuidString)", title: "День \(order)", order: order, lessons: [])
    }

    func payload(order: Int) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "order": order,
            "days": orderedDays.enumerated().map { index, day in day.payload(order: index + 1) }
        ]
        if let icon, !icon.x5Trimmed.isEmpty {
            dict["icon"] = icon
        }
        return dict
    }

    private static var timestamp: Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}

private struct EditableDay: Identifiable, Equatable {
    var id: String
    var title: String
    var order: Int
    var lessons: [EditableLesson]

    init(id: String, title: String, order: Int, lessons: [EditableLesson]) {
        self.id = id
        self.title = title
        self.order = order
        self.lessons = lessons
    }

    init(_ day: CourseDay) {
        self.id = day.id
        self.title = day.title
        self.order = day.order ?? 0
        self.lessons = day.lessons.map(EditableLesson.init)
    }

    var orderedLessons: [EditableLesson] {
        lessons.sorted { $0.order < $1.order }
    }

    func payload(order: Int) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "order": order,
            "lessons": orderedLessons.enumerated().map { index, lesson in lesson.payload(order: index + 1) }
        ]
    }
}

private struct EditableLesson: Identifiable, Equatable {
    var id: String
    var title: String
    var duration: String
    var order: Int
    var price: String
    var videoUrl: String
    var youtubeUrl: String
    var thumbnailUrl: String
    var isFreePreview: Bool
    var sellSeparately: Bool
    var pendingVideoFileURL: URL?
    var pendingVideoFileName: String?
    var pendingThumbnailData: Data?

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
        self.id = id
        self.title = title
        self.duration = duration
        self.order = order
        self.price = price
        self.videoUrl = videoUrl
        self.youtubeUrl = youtubeUrl
        self.thumbnailUrl = thumbnailUrl
        self.isFreePreview = isFreePreview
        self.sellSeparately = sellSeparately
        self.pendingVideoFileURL = pendingVideoFileURL
        self.pendingVideoFileName = pendingVideoFileName
        self.pendingThumbnailData = pendingThumbnailData
    }

    init(_ lesson: CourseLesson) {
        self.id = lesson.id
        self.title = lesson.title
        self.duration = lesson.duration ?? ""
        self.order = lesson.order ?? 0
        self.price = String(lesson.price ?? 0)
        self.videoUrl = lesson.videoUrl ?? ""
        self.youtubeUrl = lesson.youtubeUrl ?? ""
        self.thumbnailUrl = lesson.thumbnailUrl ?? ""
        self.isFreePreview = lesson.isFreePreview ?? false
        self.sellSeparately = lesson.sellSeparately ?? false
        self.pendingVideoFileURL = nil
        self.pendingVideoFileName = nil
        self.pendingThumbnailData = nil
    }

    static func new(order: Int) -> EditableLesson {
        EditableLesson(
            id: "lesson_\(Int(Date().timeIntervalSince1970 * 1000))",
            title: "",
            duration: "",
            order: order,
            price: "0",
            videoUrl: "",
            youtubeUrl: "",
            thumbnailUrl: "",
            isFreePreview: false,
            sellSeparately: false,
            pendingThumbnailData: nil
        )
    }

    var hasVideo: Bool {
        pendingVideoFileURL != nil || !videoUrl.x5Trimmed.isEmpty || !youtubeUrl.x5Trimmed.isEmpty
    }

    var videoLabel: String {
        if let pendingVideoFileName, !pendingVideoFileName.x5Trimmed.isEmpty { return pendingVideoFileName }
        if !videoUrl.x5Trimmed.isEmpty { return "Video URL" }
        if !youtubeUrl.x5Trimmed.isEmpty { return "YouTube" }
        return "Видео не задано"
    }

    func payload(order: Int) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "order": order,
            "price": Int(price) ?? 0,
            "isFreePreview": isFreePreview,
            "sellSeparately": sellSeparately
        ]
        if !duration.x5Trimmed.isEmpty { dict["duration"] = duration.x5Trimmed }
        if !videoUrl.x5Trimmed.isEmpty { dict["videoUrl"] = videoUrl.x5Trimmed }
        if !youtubeUrl.x5Trimmed.isEmpty { dict["youtubeUrl"] = youtubeUrl.x5Trimmed }
        if !thumbnailUrl.x5Trimmed.isEmpty { dict["thumbnailUrl"] = thumbnailUrl.x5Trimmed }
        return dict
    }
}

private struct LessonDraftRow: View {
    let lesson: EditableLesson

    var body: some View {
        HStack(spacing: 12) {
            lessonThumb

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title.x5Trimmed.isEmpty ? "Новый урок" : lesson.title)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(lesson.videoLabel)
                    if !lesson.duration.x5Trimmed.isEmpty {
                        Text(lesson.duration)
                    }
                    if lesson.isFreePreview {
                        Text("Бесплатный preview")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var lessonThumb: some View {
        ZStack {
            if let data = lesson.pendingThumbnailData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let url = URL(string: lesson.thumbnailUrl), !lesson.thumbnailUrl.x5Trimmed.isEmpty {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    thumbPlaceholder
                }
            } else {
                thumbPlaceholder
            }

            Image(systemName: lesson.hasVideo ? "play.fill" : "play.slash")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(lesson.hasVideo ? Color.black : .white.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(lesson.hasVideo ? Color.accentColor : Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .frame(width: 58, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var thumbPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct LessonEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let lesson: EditableLesson
    let uploadBlockerText: String?
    let uploadsImmediately: Bool
    let uploadVideo: (URL) async -> LessonVideoUploadResult
    let uploadThumbnail: (Data) async -> LessonThumbnailUploadResult
    let onSave: (EditableLesson) -> Void

    @State private var title: String
    @State private var duration: String
    @State private var price: String
    @State private var videoUrl: String
    @State private var youtubeUrl: String
    @State private var thumbnailUrl: String
    @State private var isFreePreview: Bool
    @State private var sellSeparately: Bool
    @State private var pendingVideoFileURL: URL?
    @State private var pendingVideoFileName: String?
    @State private var pendingThumbnailData: Data?
    @State private var thumbnailItem: PhotosPickerItem?
    @State private var showingImporter = false
    @State private var uploading = false
    @State private var uploadingThumbnail = false
    @State private var errorText: String?

    init(
        lesson: EditableLesson,
        uploadBlockerText: String?,
        uploadsImmediately: Bool,
        uploadVideo: @escaping (URL) async -> LessonVideoUploadResult,
        uploadThumbnail: @escaping (Data) async -> LessonThumbnailUploadResult,
        onSave: @escaping (EditableLesson) -> Void
    ) {
        self.lesson = lesson
        self.uploadBlockerText = uploadBlockerText
        self.uploadsImmediately = uploadsImmediately
        self.uploadVideo = uploadVideo
        self.uploadThumbnail = uploadThumbnail
        self.onSave = onSave
        _title = State(initialValue: lesson.title)
        _duration = State(initialValue: lesson.duration)
        _price = State(initialValue: lesson.price)
        _videoUrl = State(initialValue: lesson.videoUrl)
        _youtubeUrl = State(initialValue: lesson.youtubeUrl)
        _thumbnailUrl = State(initialValue: lesson.thumbnailUrl)
        _isFreePreview = State(initialValue: lesson.isFreePreview)
        _sellSeparately = State(initialValue: lesson.sellSeparately)
        _pendingVideoFileURL = State(initialValue: lesson.pendingVideoFileURL)
        _pendingVideoFileName = State(initialValue: lesson.pendingVideoFileName)
        _pendingThumbnailData = State(initialValue: lesson.pendingThumbnailData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Урок") {
                    TextField("Название урока", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Длительность, например 12:30", text: $duration)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("Бесплатный preview", isOn: $isFreePreview)
                }

                Section {
                    thumbnailPicker

                    TextField("MP4/HLS URL", text: $videoUrl, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)
                    TextField("YouTube URL", text: $youtubeUrl, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)

                    Button {
                        showingImporter = true
                    } label: {
                        Label(videoImportTitle, systemImage: "square.and.arrow.up")
                    }
                    .disabled(uploading || uploadBlockerText != nil)

                    if let pendingVideoFileName {
                        Label(pendingVideoFileName, systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let uploadBlockerText {
                        Text(uploadBlockerText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Видео")
                } footer: {
                    Text("Обложка сохраняется для конкретного видео. В новом курсе видео и обложка загрузятся при сохранении; в существующем уроке импорт сразу заменит ссылку.")
                }

                Section("Отдельная продажа") {
                    Toggle("Продавать отдельно", isOn: $sellSeparately)
                    if sellSeparately {
                        HStack {
                            Text("Цена")
                            Spacer()
                            TextField("0", text: $price)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(.red) }
                }
            }
            .navigationTitle("Урок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(updatedLesson())
                        dismiss()
                    }
                    .disabled(title.x5Trimmed.isEmpty || uploading || uploadingThumbnail)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await importVideo(url) }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .onChange(of: thumbnailItem) { newValue in
                guard let newValue else { return }
                Task { await importThumbnail(newValue) }
            }
        }
    }

    @ViewBuilder
    private var thumbnailPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Обложка видео")
                .font(.subheadline.weight(.semibold))

            PhotosPicker(selection: $thumbnailItem, matching: .images) {
                ZStack {
                    if let data = pendingThumbnailData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else if let url = URL(string: thumbnailUrl), !thumbnailUrl.x5Trimmed.isEmpty {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            thumbnailPlaceholder
                        }
                    } else {
                        thumbnailPlaceholder
                    }

                    if uploadingThumbnail {
                        Color.black.opacity(0.38)
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 154)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(uploadingThumbnail)

            HStack {
                PhotosPicker(selection: $thumbnailItem, matching: .images) {
                    Label(thumbnailActionTitle, systemImage: "photo.on.rectangle")
                }
                .disabled(uploadingThumbnail)

                Spacer()

                if pendingThumbnailData != nil || !thumbnailUrl.x5Trimmed.isEmpty {
                    Button(role: .destructive) {
                        pendingThumbnailData = nil
                        thumbnailUrl = ""
                    } label: {
                        Label("Убрать", systemImage: "trash")
                    }
                    .disabled(uploadingThumbnail)
                }
            }
            .font(.footnote)

            TextField("Thumbnail URL", text: $thumbnailUrl, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...3)
        }
    }

    private var thumbnailActionTitle: String {
        if uploadingThumbnail { return "Загрузка..." }
        if pendingThumbnailData != nil || !thumbnailUrl.x5Trimmed.isEmpty { return "Заменить обложку" }
        return "Добавить обложку"
    }

    private var thumbnailPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 28, weight: .light))
            Text("Добавить обложку видео")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.62))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    private var videoImportTitle: String {
        if uploading { return "Загрузка..." }
        if pendingVideoFileURL != nil || !videoUrl.x5Trimmed.isEmpty { return "Заменить видеофайл" }
        return "Импортировать видеофайл"
    }

    private func importVideo(_ url: URL) async {
        uploading = true
        defer { uploading = false }
        errorText = nil

        guard uploadsImmediately else {
            stagePendingVideo(url)
            return
        }

        let result = await uploadVideo(url)
        if let publicURL = result.url {
            videoUrl = publicURL
            pendingVideoFileURL = nil
            pendingVideoFileName = nil
        } else {
            errorText = result.error ?? "Видео не загружено."
        }
    }

    private func importThumbnail(_ item: PhotosPickerItem) async {
        uploadingThumbnail = true
        defer { uploadingThumbnail = false }
        errorText = nil

        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data),
              let jpeg = ui.jpegData(compressionQuality: 0.84) else {
            errorText = "Не удалось прочитать обложку."
            return
        }

        guard uploadsImmediately else {
            thumbnailUrl = ""
            pendingThumbnailData = jpeg
            return
        }

        let result = await uploadThumbnail(jpeg)
        if let publicURL = result.url {
            thumbnailUrl = publicURL
            pendingThumbnailData = nil
        } else {
            pendingThumbnailData = jpeg
            errorText = result.error ?? "Обложка не загружена."
        }
    }

    private func stagePendingVideo(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("x5-course-videos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let ext = normalizedVideoExtension(from: url)
            let fileName = "\(lesson.id)-\(UUID().uuidString).\(ext)"
            let destination = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)

            videoUrl = ""
            pendingVideoFileURL = destination
            pendingVideoFileName = url.lastPathComponent
        } catch {
            errorText = "Не удалось подготовить видеофайл: \(error.localizedDescription)"
        }
    }

    private func normalizedVideoExtension(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return "mp4" }
        switch ext {
        case "mov", "m4v", "mp4": return ext
        default: return "mp4"
        }
    }

    private func updatedLesson() -> EditableLesson {
        EditableLesson(
            id: lesson.id,
            title: title.x5Trimmed,
            duration: duration.x5Trimmed,
            order: lesson.order,
            price: price.x5Trimmed.isEmpty ? "0" : price.x5Trimmed,
            videoUrl: videoUrl.x5Trimmed,
            youtubeUrl: youtubeUrl.x5Trimmed,
            thumbnailUrl: thumbnailUrl.x5Trimmed,
            isFreePreview: isFreePreview,
            sellSeparately: sellSeparately,
            pendingVideoFileURL: pendingVideoFileURL,
            pendingVideoFileName: pendingVideoFileName,
            pendingThumbnailData: pendingThumbnailData
        )
    }
}

private struct LessonVideoUploadResult {
    let url: String?
    let error: String?

    static func success(_ url: String) -> LessonVideoUploadResult {
        LessonVideoUploadResult(url: url, error: nil)
    }

    static func failure(_ error: String) -> LessonVideoUploadResult {
        LessonVideoUploadResult(url: nil, error: error)
    }
}

private struct LessonThumbnailUploadResult {
    let url: String?
    let error: String?

    static func success(_ url: String) -> LessonThumbnailUploadResult {
        LessonThumbnailUploadResult(url: url, error: nil)
    }

    static func failure(_ error: String) -> LessonThumbnailUploadResult {
        LessonThumbnailUploadResult(url: nil, error: error)
    }
}

private extension String {
    var x5Trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
