import SwiftUI

/// Hub bottom tab: specialists marketplace and open tasks.
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

    var body: some View {
        NavigationStack {
            ZStack {
                HubBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hubHeader

                        HubSegmentedControl(
                            selected: $segment,
                            specialistsTitle: loc.t("hub_specialists"),
                            tasksTitle: loc.t("hub_tasks")
                        )

                        Text("CATEGORIES")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.34))
                            .tracking(1.2)

                        categoryGrid

                        switch segment {
                        case .specialists:
                            specialistsList
                        case .tasks:
                            tasksList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await service.loadSpecialists()
                    await service.loadTasks()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .alert("Chat did not open", isPresented: Binding(
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
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            headerButton
        }
    }

    @ViewBuilder
    private var headerButton: some View {
        if segment == .tasks {
            Button {
                showingPostTask = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .hubGlass(cornerRadius: 18, accent: HubPalette.cyan.opacity(0.38))
            }
            .buttonStyle(.plain)
        } else if !(currentUser.profile?.showInHub ?? false) {
            Button {
                NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "profile"])
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .hubGlass(cornerRadius: 18, accent: HubPalette.cyan.opacity(0.38))
            }
            .buttonStyle(.plain)
        } else {
            Button {} label: {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(width: 48, height: 48)
                    .hubGlass(cornerRadius: 18, accent: Color.white.opacity(0.16))
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(HubCategories.all) { cat in
                HubCategoryCard(
                    title: cat.labelEn,
                    systemImage: categoryIcon(for: cat.id),
                    count: categoryCount(for: cat.id),
                    isSelected: category == cat.id
                ) {
                    category = (category == cat.id) ? nil : cat.id
                }
            }
        }
    }

    private var specialistsList: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HubListHeader(
                title: category.map { HubCategories.label(for: $0) } ?? loc.t("hub_specialists"),
                isFiltered: category != nil
            ) {
                category = nil
            }

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
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .hubGlass(cornerRadius: 18, accent: HubPalette.cyan.opacity(0.36))
                    }
                    .buttonStyle(.plain)
                    .disabled(openingChatWith != nil)
                }
            }

            if filteredSpecialists.isEmpty && !service.isLoading {
                EmptyState(systemImage: "person.crop.circle.badge.questionmark",
                           title: loc.t("hub_no_specialists"),
                           subtitle: loc.t("hub_no_specialists_sub"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
            }
        }
    }

    private var tasksList: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HubListHeader(
                title: category.map { HubCategories.label(for: $0) } ?? loc.t("hub_tasks"),
                isFiltered: category != nil
            ) {
                category = nil
            }

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
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
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

    private func startChat(with person: HubSpecialist) {
        guard let myId = auth.userId, let token = auth.accessToken else {
            chatError = "Sign in first."
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

    private func categoryCount(for id: String) -> Int {
        switch segment {
        case .specialists:
            return service.specialists
                .filter { !BlockList.contains($0.id) }
                .filter { ($0.specialistCategory ?? []).contains(id) }
                .count
        case .tasks:
            return service.tasks
                .filter { !BlockList.contains($0.authorId) }
                .filter { $0.category == id }
                .count
        }
    }

    private func categoryIcon(for id: String) -> String {
        switch id {
        case "marketing": return "megaphone.fill"
        case "smm": return "iphone"
        case "targeting": return "scope"
        case "seo": return "magnifyingglass"
        case "sales": return "dollarsign.circle.fill"
        case "design": return "paintpalette.fill"
        case "ui_ux": return "ruler.fill"
        case "motion": return "sparkles"
        case "3d": return "cube.transparent.fill"
        case "web_dev": return "globe"
        case "mobile_dev": return "apps.iphone"
        case "bot_dev": return "cpu.fill"
        case "ai_ml": return "brain.head.profile"
        case "gamedev": return "gamecontroller.fill"
        case "ugc": return "video.fill"
        case "copy": return "pencil.and.outline"
        case "video": return "clapperboard.fill"
        case "photo": return "camera.fill"
        case "audio": return "waveform"
        case "animation": return "film.fill"
        case "translation": return "textformat"
        case "consulting": return "briefcase.fill"
        case "finance": return "chart.bar.fill"
        case "legal": return "scale.3d"
        case "hr": return "person.2.fill"
        case "education": return "graduationcap.fill"
        case "assistant": return "list.clipboard.fill"
        default: return "wrench.adjustable.fill"
        }
    }
}

// MARK: - Background

private enum HubPalette {
    static let cyan = Color(red: 0.22, green: 0.86, blue: 1.0)
    static let silver = Color(red: 0.78, green: 0.82, blue: 0.88)
    static let panel = Color(red: 0.045, green: 0.05, blue: 0.075)
}

private struct HubBackdrop: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Text("X5")
                .font(.system(size: 188, weight: .black, design: .rounded))
                .foregroundColor(HubPalette.cyan.opacity(0.13))
                .blur(radius: 2)
                .offset(x: -58, y: -250)

            Text("HUB")
                .font(.system(size: 132, weight: .black, design: .rounded))
                .foregroundColor(Color.white.opacity(0.06))
                .blur(radius: 1)
                .offset(x: 70, y: -162)

            RadialGradient(colors: [
                HubPalette.cyan.opacity(0.38),
                HubPalette.cyan.opacity(0.12),
                Color.clear
            ], center: .topTrailing, startRadius: 14, endRadius: 360)
            .ignoresSafeArea()

            RadialGradient(colors: [
                Color.white.opacity(0.18),
                Color.clear
            ], center: UnitPoint(x: 0.18, y: 0.11), startRadius: 8, endRadius: 180)
            .ignoresSafeArea()

            LinearGradient(colors: [
                Color.black.opacity(0.18),
                Color(red: 0.02, green: 0.025, blue: 0.04).opacity(0.72),
                Color.black
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

private struct HubGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(
                LinearGradient(colors: [
                    Color.white.opacity(0.17),
                    HubPalette.panel.opacity(0.50),
                    Color.white.opacity(0.045)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.05),
                            Color.clear
                        ], center: .topLeading, startRadius: 2, endRadius: 90)
                    )
                    .blendMode(.screen)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [
                            Color.white.opacity(0.34),
                            accent,
                            Color.white.opacity(0.08)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

private extension View {
    func hubGlass(cornerRadius: CGFloat, accent: Color = Color.white.opacity(0.18)) -> some View {
        modifier(HubGlassModifier(cornerRadius: cornerRadius, accent: accent))
    }
}

// MARK: - Controls

private struct HubSegmentedControl: View {
    @Binding var selected: HubView.Segment
    let specialistsTitle: String
    let tasksTitle: String

    var body: some View {
        HStack(spacing: 4) {
            segmentButton(.specialists, title: specialistsTitle)
            segmentButton(.tasks, title: tasksTitle)
        }
        .padding(5)
        .hubGlass(cornerRadius: 16, accent: Color.white.opacity(0.14))
    }

    private func segmentButton(_ segment: HubView.Segment, title: String) -> some View {
        Button {
            selected = segment
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(selected == segment ? .black : .white.opacity(0.58))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Group {
                        if selected == segment {
                            LinearGradient(colors: [
                                Color.white.opacity(0.94),
                                HubPalette.cyan.opacity(0.88)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            Color.clear
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HubCategoryCard: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .black : HubPalette.silver)
                    .frame(height: 26)

                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .frame(maxWidth: .infinity, minHeight: 30)

                Text("\(count)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(isSelected ? .black.opacity(0.62) : HubPalette.cyan.opacity(count > 0 ? 0.88 : 0.28))
                    .opacity(count > 0 ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(colors: [
                            Color.white.opacity(0.96),
                            HubPalette.cyan.opacity(0.86)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color.clear
                    }
                }
            )
            .hubGlass(cornerRadius: 14, accent: isSelected ? HubPalette.cyan.opacity(0.62) : Color.white.opacity(0.13))
        }
        .buttonStyle(.plain)
    }
}

private struct HubListHeader: View {
    let title: String
    let isFiltered: Bool
    let clear: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            if isFiltered {
                Button(action: clear) {
                    Text("All")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .hubGlass(cornerRadius: 12, accent: HubPalette.cyan.opacity(0.24))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
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
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if person.isVerified == true {
                        VerifiedChip(size: 12)
                    }

                    if person.plan == "pro" {
                        Text("PRO")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(HubPalette.cyan)
                            .clipShape(Capsule())
                    }
                }

                Text(categoryLabel.isEmpty ? "Specialist" : categoryLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(HubPalette.cyan.opacity(0.86))

                if let bio = person.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.56))
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.34))
        }
        .padding(12)
        .hubGlass(cornerRadius: 18, accent: Color.white.opacity(0.13))
    }

    private var categoryLabel: String {
        let ids = person.specialistCategory ?? []
        return ids.prefix(2).map { HubCategories.label(for: $0) }.joined(separator: " / ")
    }
}

private struct TaskRow: View {
    let task: HubTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(HubCategories.label(for: task.category))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(HubPalette.cyan)
                }

                Spacer()

                if let budget = task.budget, !budget.isEmpty {
                    Text(budget)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            if let desc = task.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.56))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                AvatarView(urlString: task.authorAvatar, name: task.authorName, size: 22)
                Text(task.authorName ?? "Anonymous")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.56))

                Spacer()

                if let deadline = task.deadline, !deadline.isEmpty {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.42))
                    Text(formatDate(deadline))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.42))
                }
            }
        }
        .padding(12)
        .hubGlass(cornerRadius: 18, accent: Color.white.opacity(0.13))
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
        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [HubPalette.cyan, .white.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
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
                .foregroundColor(.white.opacity(0.44))
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
