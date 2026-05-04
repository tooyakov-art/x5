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
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { await service.loadCourses() }
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle("CourseUP")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if isDev {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editorTarget = .create
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Создать").bold()
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
                            .background(Color.orange)
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
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(.yellow)
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

struct CourseDetailView: View {
    let course: Course
    var openPaywall: () -> Void

    @EnvironmentObject private var sub: Subscription
    @EnvironmentObject private var loc: LocalizationService

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

                Text(loc.t("courses_lessons_section"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 8)

                ForEach(course.categories.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) })) { category in
                    CategorySection(category: category, hasFullAccess: hasFullAccess, openPaywall: openPaywall)
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

private struct CategorySection: View {
    let category: CourseCategory
    let hasFullAccess: Bool
    let openPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 4)

            ForEach(category.days.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) })) { day in
                DaySection(day: day, hasFullAccess: hasFullAccess, openPaywall: openPaywall)
            }
        }
    }
}

private struct DaySection: View {
    let day: CourseDay
    let hasFullAccess: Bool
    let openPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .padding(.leading, 4)

            VStack(spacing: 6) {
                ForEach(day.lessons.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) })) { lesson in
                    LessonRow(lesson: lesson, hasFullAccess: hasFullAccess, openPaywall: openPaywall)
                }
            }
        }
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
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
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
