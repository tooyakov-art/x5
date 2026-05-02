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

                CategoryRail(selected: $category)

                Group {
                    switch segment {
                    case .specialists: specialistsList
                    case .tasks:       tasksList
                    }
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
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
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    } else if !(currentUser.profile?.showInHub ?? false) {
                        Button {
                            showingEditProfile = true
                        } label: {
                            Text(loc.t("hub_become_specialist"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.accentColor)
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
        }
    }

    private func startChat(with person: HubSpecialist) {
        guard let myId = auth.userId, let token = auth.accessToken else { return }
        openingChatWith = person.id
        Task {
            let chat = await chats.ensureChat(otherUserId: person.id, currentUserId: myId, taskId: nil, taskTitle: nil, accessToken: token)
            openingChatWith = nil
            if let chat { startingChat = chat }
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
                            .background(Color.accentColor.opacity(0.12))
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

// MARK: - Category rail

private struct CategoryRail: View {
    @Binding var selected: String?
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Pill(label: loc.t("hub_all"), isSelected: selected == nil) { selected = nil }
                ForEach(HubCategories.all) { cat in
                    Pill(label: "\(cat.emoji) \(cat.labelEn)", isSelected: selected == cat.id) {
                        selected = (selected == cat.id) ? nil : cat.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

private struct Pill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color.white.opacity(0.06))
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
        .background(Color.white.opacity(0.05))
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
        .background(Color.white.opacity(0.05))
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
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
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
