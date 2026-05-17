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
                Picker("", selection: $segment) {
                    ForEach(Segment.allCases) { s in
                        Text(s == .specialists ? loc.t("hub_specialists") : loc.t("hub_tasks")).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

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
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        if let id = category {
                            Text("\(HubCategories.all.first(where: { $0.id == id })?.emoji ?? "")  \(HubCategories.label(for: id))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
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
                        tasksList
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
                            .background(.ultraThinMaterial)
                            .overlay(
                                Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                    } else if !(currentUser.profile?.showInHub ?? false) {
                        Button {
                            NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "profile"])
                        } label: {
                            Text(loc.t("hub_become_specialist"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .overlay(
                                    Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                                )
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

    // MARK: - Сетка категорий (главный экран Hub)

    private var categoriesGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                spacing: 12
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await service.loadSpecialists() }
    }

    private func countForCategory(_ id: String) -> Int {
        service.specialists
            .filter { !BlockList.contains($0.id) }
            .filter { ($0.specialistCategory ?? []).contains(id) }
            .count
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

// MARK: - Background

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

            // Steam-style синий glow вместо старого зелёного
            RadialGradient(colors: [
                Color(red: 0.15, green: 0.50, blue: 0.85).opacity(0.20),
                Color.clear
            ], center: .bottomLeading, startRadius: 20, endRadius: 320)
            .ignoresSafeArea()
            .blur(radius: 24)
        }
    }
}

// MARK: - Tile категории

private struct CategoryTile: View {
    let cat: HubCategory
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(cat.emoji)
                .font(.system(size: 34))
            Text(cat.labelEn)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [
                Color.white.opacity(0.09),
                Color.white.opacity(0.025)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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