import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var sub: Subscription
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var service = CoursesService()
    @State private var showingPaywall = false
    @State private var editorTarget: EditorTarget?

    private var isDev: Bool { Roles.isDeveloper(auth.userEmail) }

    /// Sheet payload — `.create` for new course, `.edit(course)` for existing.
    private enum EditorTarget: Identifiable {
        case create
        case edit(Course)
        var id: String {
            switch self {
            case .create: return "_new"
            case .edit(let c): return c.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.courses.isEmpty {
                    ProgressView().tint(.accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = service.error, service.courses.isEmpty {
                    ErrorState(message: err) {
                        Task { await service.loadCourses() }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(service.courses) { course in
                                ZStack(alignment: .topLeading) {
                                    NavigationLink {
                                        CourseDetailView(course: course, openPaywall: { showingPaywall = true })
                                    } label: {
                                        CourseCard(course: course, showHiddenBadge: isDev && course.isPublic == false)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if isDev {
                                            Button {
                                                editorTarget = .edit(course)
                                            } label: {
                                                Label("Редактировать", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                Task {
                                                    guard let token = auth.accessToken else { return }
                                                    _ = await service.deleteCourse(id: course.id, accessToken: token)
                                                    await service.loadCourses(includeHidden: isDev)
                                                }
                                            } label: {
                                                Label("Удалить", systemImage: "trash")
                                            }
                                        }
                                    }

                                    // Visible edit button for developers (overlay top-left)
                                    if isDev {
                                        Button {
                                            editorTarget = .edit(course)
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.black)
                                                .frame(width: 36, height: 36)
                                                .background(Color.accentColor)
                                                .clipShape(Circle())
                                                .shadow(color: .black.opacity(0.4), radius: 6)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(12)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Следующие курсы")
                                            .font(.system(size: 22, weight: .heavy))
                                            .foregroundColor(.white)
                                        Text("Уже в плане CourseUP")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.46))
                                    }
                                    Spacer()
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.top, 8)

                                ForEach(Self.upcomingCourses) { course in
                                    NavigationLink {
                                        CourseInDevelopmentView(course: course)
                                    } label: {
                                        UpcomingCourseCard(course: course)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { await service.loadCourses() }
                }
            }
            .background { X5Background() }
            .navigationTitle("CourseUP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if isDev {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editorTarget = .create
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text(loc.t("courses_create_btn")).bold()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                } else if !sub.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingPaywall = true } label: {
                            Text(loc.t("courses_pro_chip"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(item: $editorTarget) { target in
                switch target {
                case .create:
                    CourseEditorView(editing: nil) {
                        Task { await service.loadCourses(includeHidden: isDev) }
                    }
                case .edit(let course):
                    CourseEditorView(editing: course) {
                        Task { await service.loadCourses(includeHidden: isDev) }
                    }
                }
            }
            .task { await service.loadCourses(includeHidden: isDev) }
        }
    }

    private static let upcomingCourses: [Course] = [
        makeUpcomingCourse(
            id: "upcoming-vibecoding",
            title: "Вайбкодинг для маркетолога",
            description: "Собери лендинг, квиз и Telegram-бота без команды разработки",
            lessons: ["Как ставить задачу ИИ", "Лендинг за вечер", "Форма заявки и аналитика", "Публикация и проверка"]
        ),
        makeUpcomingCourse(
            id: "upcoming-ai-reels",
            title: "AI Reels и TikTok",
            description: "Сценарии, аватары, липсинк и монтаж коротких роликов",
            lessons: ["Хук в первые 2 секунды", "ИИ-аватар", "Озвучка и липсинк", "Пакет роликов на неделю"]
        ),
        makeUpcomingCourse(
            id: "upcoming-marketplace",
            title: "Карточки товара",
            description: "Фото, инфографика и тексты для Kaspi, Wildberries и сайта",
            lessons: ["Главное фото", "Инфографика выгод", "A/B варианты", "Подготовка к загрузке"]
        ),
        makeUpcomingCourse(
            id: "upcoming-smm-system",
            title: "SMM-система на месяц",
            description: "Контент-план, рубрики, сторис и прогрев без хаоса",
            lessons: ["Рубрикатор", "30 идей постов", "Сторис-воронки", "Еженедельный отчет"]
        ),
        makeUpcomingCourse(
            id: "upcoming-youtube",
            title: "Обложки YouTube",
            description: "Превью, заголовки и визуальная упаковка роликов",
            lessons: ["Кликабельная идея", "Композиция лица", "Текст на обложке", "Серия в одном стиле"]
        ),
        makeUpcomingCourse(
            id: "upcoming-target-analytics",
            title: "Таргет и аналитика",
            description: "Связки, гипотезы, бюджет и понятный отчет по рекламе",
            lessons: ["Оффер и аудитория", "Креативы для теста", "Запуск кампании", "Что отключать первым"]
        )
    ]

    private static func makeUpcomingCourse(id: String, title: String, description: String, lessons: [String]) -> Course {
        Course(
            id: id,
            title: title,
            description: description,
            marketingHook: nil,
            coverUrl: nil,
            authorName: "X5 CourseUP",
            price: 0,
            isFree: true,
            isPublic: true,
            courseLanguage: "ru",
            averageRating: nil,
            studentsCount: nil,
            sortOrder: nil,
            categoriesRaw: [
                CourseCategory(
                    id: "\(id)-cat",
                    title: "Программа",
                    order: 1,
                    icon: "graduationcap",
                    days: [
                        CourseDay(
                            id: "\(id)-day",
                            title: "Модули",
                            order: 1,
                            lessons: lessons.enumerated().map { index, title in
                                CourseLesson(
                                    id: "\(id)-lesson-\(index + 1)",
                                    title: title,
                                    duration: "08:00",
                                    order: index + 1,
                                    price: nil,
                                    videoUrl: nil,
                                    youtubeUrl: nil,
                                    thumbnailUrl: nil,
                                    isFreePreview: index == 0,
                                    sellSeparately: false
                                )
                            }
                        )
                    ]
                )
            ]
        )
    }
}

/// Big card with cover image taking ~50% of card height — matches web Академия style.
private struct CourseCard: View {
    let course: Course
    var showHiddenBadge: Bool = false
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let cover = course.coverUrl, !cover.isEmpty, let url = URL(string: cover) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "graduationcap")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    Image(systemName: "play.circle")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(height: 220)
            .clipped()
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if showHiddenBadge {
                        Text(loc.t("courses_draft"))
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.86))
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                    }
                    if !(course.isFree ?? false) && (course.price ?? 0) > 0 {
                        Text(loc.t("courses_pro_chip").uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(course.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let desc = course.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }

                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Image(systemName: "book").font(.system(size: 11))
                        Text("\(course.totalLessons) уроков").font(.system(size: 12))
                    }.foregroundColor(.white.opacity(0.5))

                    if let students = course.studentsCount, students > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "person.2").font(.system(size: 11))
                            Text("\(students)").font(.system(size: 12))
                        }.foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    ZStack {
                        Circle().fill(Color.accentColor)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .frame(width: 36, height: 36)
                }
            }
            .padding(14)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CourseRow: View {
    let course: Course
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                if let cover = course.coverUrl, !cover.isEmpty, let url = URL(string: cover) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "graduationcap")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Image(systemName: "graduationcap")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(course.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !(course.isFree ?? false) && (course.price ?? 0) > 0 {
                        Text(loc.t("courses_pro_chip").uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                    }
                }
                if let summary = course.description, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text("\(course.totalLessons) \(loc.t("courses_lessons_word"))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    if !course.totalDurationLabel.isEmpty {
                        Text("·")
                            .foregroundColor(.white.opacity(0.3))
                        Text(course.totalDurationLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    if let r = course.averageRating, r > 0 {
                        Text("·")
                            .foregroundColor(.white.opacity(0.3))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(X5Style.blueSoft)
                            Text(String(format: "%.1f", r)).font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct UpcomingCourseCard: View {
    let course: Course

    private var accent: Color {
        switch course.id {
        case "upcoming-vibecoding": return X5Style.blue
        case "upcoming-ai-reels": return Color.purple
        case "upcoming-marketplace": return Color.cyan
        case "upcoming-smm-system": return Color.green
        case "upcoming-youtube": return Color.red
        case "upcoming-target-analytics": return Color.orange
        default: return Color.accentColor
        }
    }

    private var icon: String {
        switch course.id {
        case "upcoming-vibecoding": return "curlybraces"
        case "upcoming-ai-reels": return "play.rectangle.on.rectangle"
        case "upcoming-marketplace": return "shippingbox"
        case "upcoming-smm-system": return "calendar.badge.clock"
        case "upcoming-youtube": return "rectangle.on.rectangle"
        case "upcoming-target-analytics": return "scope"
        default: return "graduationcap"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        accent.opacity(0.34),
                        Color(red: 0.03, green: 0.04, blue: 0.07),
                        Color.black.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(accent.opacity(0.18))
                        Image(systemName: icon)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(accent)
                    }
                    .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COURSEUP")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(2.2)
                            .foregroundColor(.white.opacity(0.45))

                        Text(course.title)
                            .font(.system(size: 23, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text("В разработке")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .frame(height: 154)

            VStack(alignment: .leading, spacing: 10) {
                if let desc = course.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(2)
                }

                HStack(spacing: 14) {
                    Label("\(course.totalLessons) урока", systemImage: "book")
                    Label(course.totalDurationLabel.isEmpty ? "32 мин" : course.totalDurationLabel, systemImage: "clock")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.48))
            }
            .padding(16)
        }
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct CourseInDevelopmentView: View {
    let course: Course
    @State private var expandedCategoryIds: Set<String> = []
    @State private var expandedDayIds: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("CourseUP")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(.accentColor)

                    Text(course.title)
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let desc = course.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.20), Color.white.opacity(0.055)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Курс в разработке")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.white)
                        Text("Скоро добавим уроки, видео и материалы.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.58))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                programHeader

                ForEach(sortedCategories) { category in
                    CourseProgramCategorySection(
                        category: category,
                        isExpanded: categoryBinding(category.id),
                        expandedDayIds: $expandedDayIds
                    ) { lesson in
                        LockedSoonLessonRow(lesson: lesson)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .navigationTitle("В разработке")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { expandAllIfNeeded() }
    }

    private var sortedCategories: [CourseCategory] {
        course.categories.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private var allCategoryIds: Set<String> {
        Set(sortedCategories.map(\.id))
    }

    private var allDayIds: Set<String> {
        Set(sortedCategories.flatMap { $0.days.map(\.id) })
    }

    private var isFullyExpanded: Bool {
        !allCategoryIds.isEmpty && expandedCategoryIds == allCategoryIds && expandedDayIds == allDayIds
    }

    private var programHeader: some View {
        HStack {
            Text("Программа")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Button(isFullyExpanded ? "Свернуть все" : "Развернуть все") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isFullyExpanded {
                        expandedCategoryIds.removeAll()
                        expandedDayIds.removeAll()
                    } else {
                        expandedCategoryIds = allCategoryIds
                        expandedDayIds = allDayIds
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.accentColor)
        }
    }

    private func expandAllIfNeeded() {
        guard expandedCategoryIds.isEmpty, expandedDayIds.isEmpty else { return }
        expandedCategoryIds = allCategoryIds
        expandedDayIds = allDayIds
    }

    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategoryIds.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategoryIds.insert(id)
                } else {
                    expandedCategoryIds.remove(id)
                }
            }
        )
    }
}

struct CourseDetailView: View {
    let course: Course
    var openPaywall: () -> Void

    @EnvironmentObject private var sub: Subscription
    @EnvironmentObject private var loc: LocalizationService
    @State private var expandedCategoryIds: Set<String> = []
    @State private var expandedDayIds: Set<String> = []

    var hasFullAccess: Bool { (course.isFree ?? false) || (course.price ?? 0) == 0 || sub.isPro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let cover = course.coverUrl, !cover.isEmpty, let url = URL(string: cover) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.05)
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text(course.title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)

                if let hook = course.marketingHook, !hook.isEmpty {
                    Text(hook)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                if let desc = course.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    StatBubble(value: "\(course.totalLessons)", label: "lessons")
                    if !course.totalDurationLabel.isEmpty {
                        StatBubble(value: course.totalDurationLabel, label: "duration")
                    }
                    if let r = course.averageRating, r > 0 {
                        StatBubble(value: String(format: "%.1f ⭐", r), label: "\(course.studentsCount ?? 0) students")
                    }
                }

                if !hasFullAccess {
                    Button(action: openPaywall) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text(loc.t("courses_unlock_pro"))
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .cornerRadius(14)
                    }
                }

                lessonsHeader
                    .padding(.top, 8)

                ForEach(sortedCategories) { category in
                    CourseProgramCategorySection(
                        category: category,
                        isExpanded: categoryBinding(category.id),
                        expandedDayIds: $expandedDayIds
                    ) { lesson in
                        LessonRow(lesson: lesson, hasFullAccess: hasFullAccess, openPaywall: openPaywall)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { expandAllIfNeeded() }
    }

    private var sortedCategories: [CourseCategory] {
        course.categories.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private var allCategoryIds: Set<String> {
        Set(sortedCategories.map(\.id))
    }

    private var allDayIds: Set<String> {
        Set(sortedCategories.flatMap { $0.days.map(\.id) })
    }

    private var isFullyExpanded: Bool {
        !allCategoryIds.isEmpty && expandedCategoryIds == allCategoryIds && expandedDayIds == allDayIds
    }

    private var lessonsHeader: some View {
        HStack {
            Text(loc.t("courses_lessons_section"))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Button(isFullyExpanded ? "Свернуть все" : "Развернуть все") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isFullyExpanded {
                        expandedCategoryIds.removeAll()
                        expandedDayIds.removeAll()
                    } else {
                        expandedCategoryIds = allCategoryIds
                        expandedDayIds = allDayIds
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.accentColor)
        }
    }

    private func expandAllIfNeeded() {
        guard expandedCategoryIds.isEmpty, expandedDayIds.isEmpty else { return }
        expandedCategoryIds = allCategoryIds
        expandedDayIds = allDayIds
    }

    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategoryIds.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategoryIds.insert(id)
                } else {
                    expandedCategoryIds.remove(id)
                }
            }
        )
    }
}

private struct StatBubble: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CourseProgramCategorySection<LessonContent: View>: View {
    let category: CourseCategory
    let isExpanded: Binding<Bool>
    @Binding var expandedDayIds: Set<String>
    @ViewBuilder let lessonContent: (CourseLesson) -> LessonContent

    private var sortedDays: [CourseDay] {
        category.days.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private var lessonsCount: Int {
        category.days.reduce(0) { $0 + $1.lessons.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(.white)
                        Text("\(sortedDays.count) дней · \(lessonsCount) уроков")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedDays) { day in
                        CourseProgramDaySection(
                            day: day,
                            isExpanded: dayBinding(day.id),
                            lessonContent: lessonContent
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func dayBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedDayIds.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedDayIds.insert(id)
                } else {
                    expandedDayIds.remove(id)
                }
            }
        )
    }
}

private struct CourseProgramDaySection<LessonContent: View>: View {
    let day: CourseDay
    let isExpanded: Binding<Bool>
    @ViewBuilder let lessonContent: (CourseLesson) -> LessonContent

    private var sortedLessons: [CourseLesson] {
        day.lessons.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.44))
                        .frame(width: 16)

                    Text(day.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.72))

                    Spacer()

                    Text("\(sortedLessons.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.38))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(spacing: 6) {
                    ForEach(sortedLessons) { lesson in
                        lessonContent(lesson)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct LockedSoonLessonRow: View {
    let lesson: CourseLesson

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.38))
            }
            .frame(width: 32, height: 32)

            Text(lesson.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(2)

            Spacer()

            Text("скоро")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.36))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LessonRow: View {
    let lesson: CourseLesson
    let hasFullAccess: Bool
    let openPaywall: () -> Void
    @EnvironmentObject private var loc: LocalizationService

    var canPlay: Bool { hasFullAccess || lesson.freePreview }
    var hasVideo: Bool { lesson.playableURL != nil }

    var body: some View {
        Group {
            if canPlay && hasVideo {
                NavigationLink {
                    LessonPlayerView(lesson: lesson)
                } label: { content }
                .buttonStyle(.plain)
            } else {
                Button(action: { if !canPlay { openPaywall() } }) { content }
                    .buttonStyle(.plain)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: !hasVideo ? "doc.text" : (canPlay ? "play.fill" : "lock.fill"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(canPlay ? .accentColor : .white.opacity(0.45))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let d = lesson.duration, !d.isEmpty {
                        Text(d).font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                    }
                    if lesson.freePreview {
                        Text(loc.t("courses_free_preview"))
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(X5Style.blue.opacity(0.18))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            if canPlay && hasVideo {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.white.opacity(0.6))
            Text(loc.t("courses_load_failed"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry", action: retry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
