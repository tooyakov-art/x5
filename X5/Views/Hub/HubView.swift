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
    @State private var segment: Segment = .specialists
    @State private var category: String? = nil
    @State private var showingPostTask = false
    @State private var showingEditProfile = false
    @State private var openingChatWith: String? = nil
    @State private var startingChat: ChatRoom? = nil
    @State private var chatError: String? = nil

    private let hubBackground = Color(red: 0.025, green: 0.03, blue: 0.07)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HubSegmentedControl(segment: $segment,
                                    specialistsTitle: loc.t("hub_specialists"),
                                    tasksTitle: loc.t("hub_tasks"))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

                CategoryGrid(selected: $category)

                Group {
                    switch segment {
                    case .specialists: specialistsList
                    case .tasks:       tasksList
                    }
                }
            }
            .background(HubBackdrop(base: hubBackground))
            .navigationTitle(loc.t("hub_title"))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == .tasks {
                        Button {
                            showingPostTask = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text(loc.t("hub_post")).bold()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(LinearGradient(colors: [Color.accentColor, Color(red: 0.62, green: 1.0, blue: 0.18)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                        }
                    } else if !(currentUser.profile?.showInHub ?? false) {
                        Button {
                            // Open user's own Profile tab — there they edit and toggle "Show in Hub"
                            NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "profile"])
                        } label: {
                            Text(loc.t("hub_become_specialist"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(LinearGradient(colors: [Color.accentColor, Color(red: 0.62, green: 1.0, blue: 0.18)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(Capsule())
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

    private func startChat(with person: HubSpecialist) {
        guard let myId = auth.userId, let token = auth.accessToken else {
            chatError = "Сначала войди в аккаунт."
            return
        }
        openingChatWith = person.id
        Task {
            let chat = await chats.ensureChat(otherUserId: person.id, currentUserId: myId, taskId: nil, taskTitle: nil, accessToken: token)
            openingChatWith = nil
            if let chat {
                startingChat = chat
            } else {
                chatError = chats.error ?? "Не удалось открыть чат. Попробуй ещё раз."
            }
        }
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
                            .background(.ultraThinMaterial)
                            .overlay(
                                Circle().stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(Circle())
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

// MARK: - Header controls

private struct HubBackdrop: View {
    let base: Color

    var body: some View {
        ZStack {
            base.ignoresSafeArea()
            LinearGradient(colors: [
                Color(red: 0.08, green: 0.10, blue: 0.18).opacity(0.85),
                Color.clear,
                Color.black.opacity(0.20)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            RadialGradient(colors: [
                Color.accentColor.opacity(0.22),
                Color.clear
            ], center: .topTrailing, startRadius: 10, endRadius: 260)
            .ignoresSafeArea()
            .blur(radius: 18)

            RadialGradient(colors: [
                Color(red: 0.08, green: 0.62, blue: 0.48).opacity(0.16),
                Color.clear
            ], center: .bottomLeading, startRadius: 20, endRadius: 320)
            .ignoresSafeArea()
            .blur(radius: 24)
        }
    }
}

private struct HubSegmentedControl: View {
    @Binding var segment: HubView.Segment
    let specialistsTitle: String
    let tasksTitle: String

    var body: some View {
        HStack(spacing: 4) {
            segmentButton(.specialists, title: specialistsTitle, icon: "person.2.fill")
            segmentButton(.tasks, title: tasksTitle, icon: "briefcase.fill")
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func segmentButton(_ value: HubView.Segment, title: String, icon: String) -> some View {
        let selected = segment == value
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                segment = value
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Group {
                    if selected {
                        LinearGradient(colors: [Color.accentColor, Color(red: 0.68, green: 1.0, blue: 0.20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryGrid: View {
    @Binding var selected: String?
    @EnvironmentObject private var loc: LocalizationService

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var featured: [HubCategory] {
        Array(HubCategories.all.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CATEGORIES")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.42))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selected = nil
                    }
                } label: {
                    Text(loc.t("hub_all"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(selected == nil ? .black : .white.opacity(0.70))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected == nil ? Color.accentColor : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(featured) { cat in
                    CategoryTile(category: cat, selected: selected == cat.id) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selected = (selected == cat.id) ? nil : cat.id
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HubCategories.all.dropFirst(6)) { cat in
                        CompactCategoryPill(category: cat, selected: selected == cat.id) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selected = (selected == cat.id) ? nil : cat.id
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

private struct CategoryTile: View {
    let category: HubCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.black.opacity(0.18) : Color.white.opacity(0.07))
                        .frame(width: 34, height: 34)
                    Text(category.emoji)
                        .font(.system(size: 20))
                }

                Text(category.labelEn)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(selected ? .black : .white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                ZStack {
                    LinearGradient(colors: selected ? [
                        Color.accentColor,
                        Color(red: 0.70, green: 1.0, blue: 0.22)
                    ] : [
                        Color.white.opacity(0.085),
                        Color.white.opacity(0.035)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)

                    if !selected {
                        LinearGradient(colors: [
                            Color(red: 0.12, green: 0.18, blue: 0.28).opacity(0.45),
                            Color(red: 0.20, green: 0.07, blue: 0.18).opacity(0.25)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CompactCategoryPill: View {
    let category: HubCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(category.emoji)
                Text(category.labelEn)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(selected ? .black : .white.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                    Text(person.name ?? person.nickname ?? "User")
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
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [
                Color.white.opacity(0.09),
                Color.white.opacity(0.025)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [
                Color.white.opacity(0.09),
                Color.white.opacity(0.025)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
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
