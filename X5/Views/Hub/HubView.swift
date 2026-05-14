import SwiftUI

/// Hub marketplace: specialists and tasks wrapped in a premium 3-column iOS glass layout.
struct HubView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case specialists, tasks
        var id: String { rawValue }
    }

    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var service = HubService()
    @StateObject private var chats = ChatsService()
    @State private var segment: Segment = .specialists
    @State private var category: String? = nil
    @State private var showingPostTask = false
    @State private var showingEditProfile = false
    @State private var openingChatWith: String? = nil
    @State private var startingChat: ChatRoom? = nil
    @State private var chatError: String? = nil

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HubHero(
                        segment: segment,
                        specialistsCount: filteredSpecialists.count,
                        tasksCount: filteredTasks.count
                    )

                    HubSegmentControl(segment: $segment)

                    HubCategoryGrid(selected: $category, columns: gridColumns)

                    contentHeader

                    if segment == .specialists {
                        specialistsGrid
                    } else {
                        tasksGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 118)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await service.loadSpecialists()
                await service.loadTasks()
            }
            .background(HubBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HubTopBar(
                    segment: segment,
                    showPostTask: { showingPostTask = true },
                    showProfileSetup: {
                        NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "profile"])
                    },
                    needsProfileSetup: !(currentUser.profile?.showInHub ?? false)
                )
            }
            .task {
                await service.loadSpecialists()
                await service.loadTasks()
            }
            .sheet(isPresented: $showingPostTask) {
                CreateTaskView(onCreated: {
                    Task { await service.loadTasks() }
                })
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(item: $startingChat) { chat in
                NavigationStack { ChatThreadView(chat: chat) }
                    .preferredColorScheme(.dark)
            }
            .alert("Chat unavailable", isPresented: Binding(
                get: { chatError != nil },
                set: { if !$0 { chatError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(chatError ?? "")
            }
        }
    }

    private var contentHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(segment == .specialists ? loc.t("hub_specialists") : loc.t("hub_tasks"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(category.map { HubCategories.label(for: $0) } ?? "All categories")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(HubStyle.silver)
            }

            Spacer()

            Text("\(segment == .specialists ? filteredSpecialists.count : filteredTasks.count)")
                .font(.system(size: 24, weight: .thin, design: .rounded))
                .foregroundStyle(HubStyle.cyan)
        }
        .padding(.top, 2)
    }

    private var specialistsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(filteredSpecialists) { person in
                SpecialistTile(
                    person: person,
                    isOpeningChat: openingChatWith == person.id,
                    openChat: { startChat(with: person) }
                )
            }
        }
        .overlay {
            if filteredSpecialists.isEmpty && !service.isLoading {
                EmptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: loc.t("hub_no_specialists"),
                    subtitle: loc.t("hub_no_specialists_sub")
                )
                .padding(.top, 54)
            }
        }
        .frame(minHeight: filteredSpecialists.isEmpty ? 190 : nil)
    }

    private var tasksGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(filteredTasks) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    TaskTile(task: task)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if filteredTasks.isEmpty && !service.isLoading {
                EmptyState(
                    systemImage: "tray",
                    title: loc.t("hub_no_tasks"),
                    subtitle: loc.t("hub_no_tasks_sub")
                )
                .padding(.top, 54)
            }
        }
        .frame(minHeight: filteredTasks.isEmpty ? 190 : nil)
    }

    private func startChat(with person: HubSpecialist) {
        guard let myId = auth.userId, let token = auth.accessToken else {
            chatError = "Please sign in first."
            return
        }
        openingChatWith = person.id
        Task {
            let chat = await chats.ensureChat(otherUserId: person.id, currentUserId: myId, taskId: nil, taskTitle: nil, accessToken: token)
            openingChatWith = nil
            if let chat {
                startingChat = chat
            } else {
                chatError = chats.error ?? "Could not open chat. Try again."
            }
        }
    }

    private var filteredSpecialists: [HubSpecialist] {
        let visible = service.specialists.filter { !BlockList.contains($0.id) }
        guard let category else { return visible }
        return visible.filter { ($0.specialistCategory ?? []).contains(category) }
    }

    private var filteredTasks: [HubTask] {
        let visible = service.tasks.filter { !BlockList.contains($0.authorId) }
        guard let category else { return visible }
        return visible.filter { $0.category == category }
    }
}

// MARK: - Style

private enum HubStyle {
    static let black = Color.black
    static let panel = Color.white.opacity(0.055)
    static let panelStrong = Color.white.opacity(0.105)
    static let stroke = Color.white.opacity(0.145)
    static let strokeBright = Color.white.opacity(0.26)
    static let silver = Color(red: 0.72, green: 0.76, blue: 0.80)
    static let cyan = Color(red: 0.18, green: 0.82, blue: 0.96)
    static let cyanDeep = Color(red: 0.03, green: 0.28, blue: 0.42)

    static var glassGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.16),
                Color.white.opacity(0.055),
                Color.white.opacity(0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GlassTile: ViewModifier {
    var cornerRadius: CGFloat = 18
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background {
                if isSelected {
                    HubStyle.cyan.opacity(0.13)
                } else {
                    HubStyle.glassGradient
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? HubStyle.cyan.opacity(0.62) : HubStyle.stroke, lineWidth: 1)
            )
            .shadow(color: isSelected ? HubStyle.cyan.opacity(0.20) : .clear, radius: 18, x: 0, y: 10)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private extension View {
    func hubGlass(cornerRadius: CGFloat = 18, isSelected: Bool = false) -> some View {
        modifier(GlassTile(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}

// MARK: - Chrome

private struct HubBackdrop: View {
    var body: some View {
        ZStack {
            HubStyle.black.ignoresSafeArea()

            GeometryReader { proxy in
                let width = proxy.size.width

                Text("X5")
                    .font(.system(size: width * 0.64, weight: .ultraLight, design: .rounded))
                    .tracking(-18)
                    .foregroundStyle(HubStyle.cyan.opacity(0.16))
                    .blur(radius: 1.4)
                    .shadow(color: HubStyle.cyan.opacity(0.55), radius: 52, x: 0, y: 0)
                    .offset(x: -22, y: 54)

                Text("HUB")
                    .font(.system(size: width * 0.28, weight: .thin, design: .rounded))
                    .tracking(12)
                    .foregroundStyle(Color.white.opacity(0.055))
                    .rotationEffect(.degrees(-90))
                    .offset(x: width * 0.54, y: 238)

                RadialGradient(
                    colors: [
                        HubStyle.cyan.opacity(0.25),
                        HubStyle.cyanDeep.opacity(0.16),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 360
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        Color.clear
                    ],
                    center: .init(x: 0.22, y: 0.18),
                    startRadius: 0,
                    endRadius: 240
                )
            }
            .ignoresSafeArea()
        }
    }
}

private struct HubTopBar: View {
    let segment: HubView.Segment
    let showPostTask: () -> Void
    let showProfileSetup: () -> Void
    let needsProfileSetup: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("X5")
                .font(.system(size: 17, weight: .thin, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)

            Spacer()

            if segment == .tasks {
                Button(action: showPostTask) {
                    Label("Post", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(HubStyle.cyan)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if needsProfileSetup {
                Button(action: showProfileSetup) {
                    Text("Join Hub")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .hubGlass(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.96), Color.black.opacity(0.58), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct HubHero: View {
    let segment: HubView.Segment
    let specialistsCount: Int
    let tasksCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hub")
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(1)

                Spacer()

                Text("X5")
                    .font(.system(size: 18, weight: .thin, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(HubStyle.silver)
            }

            Text(segment == .specialists ? "Find premium operators" : "Open work, filtered fast")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(HubStyle.silver)

            HStack(spacing: 10) {
                HubMetric(value: "\(specialistsCount)", label: "people")
                HubMetric(value: "\(tasksCount)", label: "tasks")
                HubMetric(value: "3", label: "columns")
            }
        }
        .padding(.top, 62)
    }
}

private struct HubMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(HubStyle.silver.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hubGlass(cornerRadius: 16)
    }
}

private struct HubSegmentControl: View {
    @Binding var segment: HubView.Segment
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        HStack(spacing: 8) {
            segmentButton(.specialists, title: loc.t("hub_specialists"), icon: "person.2")
            segmentButton(.tasks, title: loc.t("hub_tasks"), icon: "briefcase")
        }
        .padding(5)
        .hubGlass(cornerRadius: 24)
    }

    private func segmentButton(_ value: HubView.Segment, title: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                segment = value
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(segment == value ? .black : .white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(segment == value ? HubStyle.cyan : Color.white.opacity(0.045))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category grid

private struct HubCategoryGrid: View {
    @Binding var selected: String?
    let columns: [GridItem]
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            CategoryCell(
                title: loc.t("hub_all"),
                icon: "circle.grid.3x3",
                isSelected: selected == nil
            ) {
                selected = nil
            }

            ForEach(Array(HubCategories.all.prefix(8))) { cat in
                CategoryCell(
                    title: cat.labelEn,
                    icon: HubIcon.symbol(for: cat.id),
                    isSelected: selected == cat.id
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selected = (selected == cat.id) ? nil : cat.id
                    }
                }
            }
        }
    }
}

private struct CategoryCell: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(isSelected ? HubStyle.cyan : .white.opacity(0.86))
                    .frame(height: 20)

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : HubStyle.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .hubGlass(cornerRadius: 18, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private enum HubIcon {
    static func symbol(for id: String?) -> String {
        switch id {
        case "marketing": return "megaphone"
        case "smm": return "rectangle.stack"
        case "targeting": return "scope"
        case "seo": return "magnifyingglass"
        case "sales": return "chart.line.uptrend.xyaxis"
        case "design": return "paintbrush.pointed"
        case "ui_ux": return "square.on.square"
        case "motion": return "sparkles"
        case "3d": return "cube.transparent"
        case "web_dev": return "globe"
        case "mobile_dev": return "iphone"
        case "bot_dev": return "bubble.left.and.bubble.right"
        case "ai_ml": return "cpu"
        case "gamedev": return "gamecontroller"
        case "ugc": return "video"
        case "copy": return "text.quote"
        case "consulting": return "briefcase"
        case "finance": return "chart.pie"
        case "legal": return "scale.3d"
        case "hr": return "person.2"
        case "education": return "graduationcap"
        default: return "circle.hexagongrid"
        }
    }
}

// MARK: - Tiles

private struct SpecialistTile: View {
    let person: HubSpecialist
    let isOpeningChat: Bool
    let openChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                UserProfileView(userId: person.id, fallback: person)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    PremiumAvatar(urlString: person.avatar, name: displayName, size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                            if person.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(HubStyle.cyan)
                            }
                        }

                        Text(categoryLabel)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(HubStyle.silver.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if person.plan == "pro" {
                    Text("PRO")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(HubStyle.cyan)
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: openChat) {
                    Group {
                        if isOpeningChat {
                            ProgressView()
                                .tint(HubStyle.cyan)
                        } else {
                            Image(systemName: "message")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HubStyle.cyan)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .hubGlass(cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .disabled(isOpeningChat)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .hubGlass(cornerRadius: 20)
    }

    private var displayName: String {
        person.name ?? person.nickname ?? "User"
    }

    private var categoryLabel: String {
        let ids = person.specialistCategory ?? []
        let label = ids.prefix(1).map { HubCategories.label(for: $0) }.joined()
        return label.isEmpty ? "Specialist" : label
    }
}

private struct TaskTile: View {
    let task: HubTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: HubIcon.symbol(for: task.category))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(HubStyle.cyan)
                .frame(width: 30, height: 30)
                .hubGlass(cornerRadius: 15)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)

                Text(HubCategories.label(for: task.category))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(HubStyle.silver.opacity(0.78))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text((task.budget?.isEmpty == false ? task.budget : "Open") ?? "Open")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(HubStyle.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(task.authorName ?? "Client")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(HubStyle.silver.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .hubGlass(cornerRadius: 20)
    }
}

private struct PremiumAvatar: View {
    let urlString: String?
    let name: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.22),
                    HubStyle.cyan.opacity(0.26),
                    Color.black.opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let parts = (name ?? "?").split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

// MARK: - Shared helpers

struct AvatarView: View {
    let urlString: String?
    let name: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [HubStyle.cyanDeep, HubStyle.cyan.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var initials: String {
        let parts = (name ?? "?").split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.36))
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.52))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
