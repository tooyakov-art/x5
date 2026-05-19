import SwiftUI

/// Hub — bottom tab matching web HireView. Two segmented sub-tabs:
/// Specialists (profiles where show_in_hub=true) and Tasks (open task marketplace).
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
    @StateObject private var portfolio = PortfolioService()
    @State private var segment: Segment = .specialists
    @State private var category: String? = nil
    @State private var showingPostTask = false
    @State private var showingAddPortfolio = false
    @State private var showingEditProfile = false
    @State private var openingChatWith: String? = nil
    @State private var startingChat: ChatRoom? = nil
    @State private var chatError: String? = nil
    @State private var selectedCountry: HubCountry = .kazakhstan

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hubHeader

                Picker("", selection: $segment) {
                    ForEach(Segment.allCases) { s in
                        Text(s == .specialists ? loc.t("hub_specialists") : loc.t("hub_tasks")).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if segment == .specialists {
                    addPortfolioButton
                } else if segment == .tasks {
                    createTaskButton
                    countrySelector
                }

                // Когда категория выбрана — показываем кнопку «назад к категориям»
                if category != nil {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { category = nil }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text(loc.t("hub_all"))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)

                        if let id = category {
                            HStack(spacing: 7) {
                                Image(systemName: hubCategorySymbol(for: id))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.accentColor)
                                Text(HubCategories.label(for: id))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                Group {
                    switch segment {
                    case .specialists:
                        if category == nil {
                            categoriesGrid
                        } else {
                            specialistsList
                        }
                    case .tasks:
                        if category == nil {
                            categoriesGrid
                        } else {
                            tasksList
                        }
                    }
                }
            }
            .background { X5Background() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if segment == .specialists && !(currentUser.profile?.showInHub ?? false) {
                        Button {
                            NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "profile"])
                        } label: {
                            Text(loc.t("hub_become_specialist"))
                        }
                    }
                }
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
            .sheet(isPresented: $showingAddPortfolio) {
                AddPortfolioItemView { data, mediaType, mime, ext, title, desc in
                    guard let token = auth.accessToken, let userId = auth.userId else {
                        chatError = "Сначала войди в аккаунт."
                        return false
                    }
                    return await portfolio.addMedia(
                        data: data,
                        type: mediaType,
                        mime: mime,
                        ext: ext,
                        userId: userId,
                        title: title,
                        description: desc,
                        accessToken: token
                    )
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(item: $startingChat) { chat in
                NavigationStack { ChatThreadView(chat: chat) }
                    .preferredColorScheme(.dark)
            }
            .alert("Чат не открылся", isPresented: Binding(
                get: { chatError != nil },
                set: { if !$0 { chatError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(chatError ?? "")
            }
        }
    }

    private var hubHeader: some View {
        HStack(alignment: .center) {
            Text(loc.t("hub_title"))
                .font(.system(size: 42, weight: .black))
                .foregroundColor(.white)
                .kerning(-1.0)
                .shadow(color: X5Style.blueSoft.opacity(0.45), radius: 18, x: 0, y: 0)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, -22)
        .padding(.bottom, 4)
    }

    private var createTaskButton: some View {
        Button {
            showingPostTask = true
        } label: {
            Label(loc.t("hub_create_task"), systemImage: "plus.circle.fill")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var addPortfolioButton: some View {
        Button {
            showingAddPortfolio = true
        } label: {
            Label(loc.t("hub_add_portfolio"), systemImage: "photo.badge.plus")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var countrySelector: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    selectedCountry = .kazakhstan
                } label: {
                    Label(loc.t(HubCountry.kazakhstan.titleKey), systemImage: "checkmark")
                }
                Section(loc.t("hub_country_soon")) {
                    ForEach(HubCountry.comingSoon) { country in
                        Button(loc.t(country.titleKey)) {}
                            .disabled(true)
                    }
                }
            } label: {
                Label(loc.t(selectedCountry.titleKey), systemImage: "location.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.18))

            Text(loc.t("hub_country_orders"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.52))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private func startChat(with person: HubSpecialist) {
        guard let myId = auth.userId else {
            chatError = "Сначала войди в аккаунт."
            return
        }
        openingChatWith = person.id
        Task {
            guard let token = await auth.freshAccessToken() else {
                openingChatWith = nil
                chatError = "Сначала войди в аккаунт."
                return
            }
            let chat = await chats.ensureChat(otherUserId: person.id, currentUserId: myId, taskId: nil, taskTitle: nil, accessToken: token)
            openingChatWith = nil
            if let chat {
                startingChat = chat
            } else {
                chatError = chats.error ?? "Не удалось открыть чат. Попробуй ещё раз."
            }
        }
    }

    // MARK: - Сетка категорий (главный экран Hub)

    private var categoriesGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 62, maximum: 92), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(HubCategories.all) { cat in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { category = cat.id }
                    } label: {
                        CategoryTile(cat: cat, count: countForCategory(cat.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refreshCurrentHubSegment() }
    }

    private func countForCategory(_ id: String) -> Int {
        if segment == .tasks {
            return taskCategoryCounts[id] ?? 0
        }
        return specialistCategoryCounts[id] ?? 0
    }

    private var specialistCategoryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for person in service.specialists where !BlockList.contains(person.id) {
            for id in person.specialistCategory ?? [] {
                counts[normalizedHubCategory(id), default: 0] += 1
            }
        }
        return counts
    }

    private var taskCategoryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for task in service.tasks where !BlockList.contains(task.authorId) {
            if let category = task.category {
                counts[normalizedHubCategory(category), default: 0] += 1
            }
        }
        return counts
    }

    private var specialistsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredSpecialists) { person in
                    HStack(spacing: 8) {
                        NavigationLink {
                            UserProfileView(userId: person.id, fallback: person)
                        } label: {
                            SpecialistRow(person: person)
                        }
                        .buttonStyle(.plain)

                        Button {
                            startChat(with: person)
                        } label: {
                            Group {
                                if openingChatWith == person.id {
                                    ProgressView().tint(.accentColor)
                                } else {
                                    Image(systemName: "message.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(openingChatWith != nil)
                    }
                }
                if filteredSpecialists.isEmpty && !service.isLoading {
                    EmptyState(systemImage: "person.crop.circle.badge.questionmark",
                               title: loc.t("hub_no_specialists"),
                               subtitle: loc.t("hub_no_specialists_sub"))
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await service.loadSpecialists() }
    }

    private var tasksList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredTasks) { task in
                    NavigationLink {
                        TaskDetailView(task: task)
                    } label: {
                        TaskRow(task: task)
                    }
                    .buttonStyle(.plain)
                }
                if filteredTasks.isEmpty && !service.isLoading {
                    EmptyState(systemImage: "tray",
                               title: loc.t("hub_no_tasks"),
                               subtitle: loc.t("hub_no_tasks_sub"))
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await service.loadTasks() }
    }

    private var filteredSpecialists: [HubSpecialist] {
        let visible = service.specialists
            .filter { !BlockList.contains($0.id) }
            .filter { $0.id != auth.userId }
        guard let category else { return visible }
        return visible.filter { person in
            (person.specialistCategory ?? []).contains { normalizedHubCategory($0) == category }
        }
    }

    private var filteredTasks: [HubTask] {
        let visible = service.tasks.filter { !BlockList.contains($0.authorId) }
        guard let category else { return visible }
        return visible.filter { normalizedHubCategory($0.category) == category }
    }

    private func refreshCurrentHubSegment() async {
        switch segment {
        case .specialists:
            await service.loadSpecialists()
        case .tasks:
            await service.loadTasks()
        }
    }
}

// MARK: - Background

private struct HubCountry: Identifiable, Hashable {
    let id: String
    let titleKey: String

    static let kazakhstan = HubCountry(id: "kz", titleKey: "country_kazakhstan")
    static let comingSoon: [HubCountry] = [
        HubCountry(id: "uz", titleKey: "country_uzbekistan"),
        HubCountry(id: "kg", titleKey: "country_kyrgyzstan"),
        HubCountry(id: "ae", titleKey: "country_uae"),
        HubCountry(id: "tr", titleKey: "country_turkey"),
        HubCountry(id: "us", titleKey: "country_usa")
    ]
}

// MARK: - Tile категории

private func hubCategorySymbol(for id: String) -> String {
    HubCategories.symbol(for: id)
}

private func normalizedHubCategory(_ value: String?) -> String {
    guard let value else { return "other" }
    let cleaned = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")

    switch cleaned {
    case "ads", "ad", "target", "target_ads", "targeting_ads", "reklama", "реклама", "таргет", "таргет_реклама":
        return "targeting"
    case "chatbot", "chatbots", "bot", "bots", "botdev", "bot_dev":
        return "bot_dev"
    case "web", "webdev", "web_development":
        return "web_dev"
    case "mobile", "mobiledev", "mobile_development":
        return "mobile_dev"
    case "ai", "ml", "ai_ml", "ai_neural", "нейросети":
        return "ai_ml"
    case "game", "game_dev":
        return "gamedev"
    case "uiux", "ui/ux", "ux_ui":
        return "ui_ux"
    default:
        return cleaned
    }
}

private struct CategoryTile: View {
    let cat: HubCategory
    let count: Int

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: hubCategorySymbol(for: cat.id))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), X5Style.blue.opacity(0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 26)
            Text(cat.labelEn)
                .font(.system(size: 10.5, weight: .heavy))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.white.opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Rows

private struct SpecialistRow: View {
    let person: HubSpecialist

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: person.avatar, name: person.name, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.name ?? person.nickname ?? "X5")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    if person.isVerified == true {
                        VerifiedChip(size: 12)
                    }
                    if person.plan == "pro" {
                        Text("PRO").font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(categoryLabel)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor.opacity(0.85))
                if let bio = person.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var categoryLabel: String {
        let ids = person.specialistCategory ?? []
        return ids.prefix(2).map { HubCategories.label(for: $0) }.joined(separator: " · ")
    }
}

private struct TaskRow: View {
    let task: HubTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(HubCategories.label(for: task.category))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Spacer()
                if let budget = task.budget, !budget.isEmpty {
                    Text(budget)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            if let desc = task.description, !desc.isEmpty {
                Text(desc).font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineLimit(2)
            }
            HStack(spacing: 8) {
                AvatarView(urlString: task.authorAvatar, name: task.authorName, size: 22)
                Text(task.authorName ?? "Anonymous")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                Spacer()
                if let deadline = task.deadline, !deadline.isEmpty {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Text(formatDate(deadline))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }
}

// MARK: - Helpers

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
            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold))
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
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.white.opacity(0.4))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
