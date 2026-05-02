import SwiftUI

/// List of all chats for the current user.
struct ChatsListView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var service = ChatsService()
    @State private var profiles: [String: UserProfile] = [:]
    /// Bumped to force `visibleChats` recomputation after archive/mute/hide.
    /// `ChatsLocalState` is a static enum so the view doesn't observe it.
    @State private var localStateTick: Int = 0
    @State private var showArchive: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.chats.isEmpty {
                    ProgressView().tint(.accentColor).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleChats.isEmpty {
                    EmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: loc.t("chats_empty_title"),
                        subtitle: loc.t("chats_empty_sub")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    chatList
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle(loc.t("chats_title"))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await reload() }
        }
    }

    @ViewBuilder
    private var chatList: some View {
        List {
            // Archive entry — only when the user actually has archived chats,
            // mirrors WhatsApp/Telegram pattern.
            if !archivedChats.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedChatsView(
                            chats: archivedChats,
                            profiles: profiles,
                            currentUserId: auth.userId ?? "",
                            onChange: { localStateTick &+= 1 }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("chats_archive"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("\(archivedChats.count)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }

            ForEach(visibleChats) { chat in
                let otherId = chat.otherParticipantId(currentUser: auth.userId ?? "") ?? ""
                ChatRowLink(
                    chat: chat,
                    currentUserId: auth.userId ?? "",
                    other: profiles[otherId],
                    peerId: otherId
                )
                .listRowBackground(Color.white.opacity(0.04))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        ChatsLocalState.hide(chat.id)
                        localStateTick &+= 1
                    } label: {
                        Label(loc.t("chats_delete"), systemImage: "trash")
                    }
                    Button {
                        ChatsLocalState.archive(chat.id)
                        localStateTick &+= 1
                    } label: {
                        Label(loc.t("chats_archive"), systemImage: "archivebox")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading) {
                    let muted = ChatsLocalState.isMuted(chat.id)
                    Button {
                        if muted { ChatsLocalState.unmute(chat.id) }
                        else { ChatsLocalState.mute(chat.id) }
                        localStateTick &+= 1
                    } label: {
                        Label(
                            muted ? loc.t("chats_unmute") : loc.t("chats_mute"),
                            systemImage: muted ? "bell" : "bell.slash"
                        )
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    let muted = ChatsLocalState.isMuted(chat.id)
                    Button {
                        if muted { ChatsLocalState.unmute(chat.id) }
                        else { ChatsLocalState.mute(chat.id) }
                        localStateTick &+= 1
                    } label: {
                        Label(
                            muted ? loc.t("chats_unmute") : loc.t("chats_mute"),
                            systemImage: muted ? "bell" : "bell.slash"
                        )
                    }
                    Button {
                        ChatsLocalState.archive(chat.id)
                        localStateTick &+= 1
                    } label: {
                        Label(loc.t("chats_archive"), systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        ChatsLocalState.hide(chat.id)
                        localStateTick &+= 1
                    } label: {
                        Label(loc.t("chats_delete"), systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .refreshable { await reload() }
        // Reading the tick here makes SwiftUI reread visibleChats / archivedChats
        // whenever local state mutations bump it.
        .id(localStateTick)
    }

    /// Server chats minus blocked peers and minus locally-hidden chats.
    private var nonBlocked: [ChatRoom] {
        let me = auth.userId ?? ""
        return service.chats.filter { chat in
            if ChatsLocalState.isHidden(chat.id) { return false }
            guard let otherId = chat.otherParticipantId(currentUser: me) else { return true }
            return !BlockList.contains(otherId)
        }
    }

    /// Active inbox — excludes archived chats.
    private var visibleChats: [ChatRoom] {
        nonBlocked.filter { !ChatsLocalState.isArchived($0.id) }
    }

    /// Archived bucket shown under the "Архив" entry.
    private var archivedChats: [ChatRoom] {
        nonBlocked.filter { ChatsLocalState.isArchived($0.id) }
    }

    private func reload() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        await service.loadChats(currentUserId: uid, accessToken: token)
        // Pre-load profiles of all peers so rows show name + avatar instead of "?"
        for chat in service.chats {
            guard let otherId = chat.otherParticipantId(currentUser: uid),
                  profiles[otherId] == nil else { continue }
            if let p = await service.loadPublicProfile(userId: otherId, accessToken: token) {
                profiles[otherId] = p
            }
        }
    }
}

/// Extracted to keep the main list builder readable. `NavigationLink` wrapping
/// a custom row label needs its own scope so swipeActions / contextMenu attach
/// cleanly without confusing the gesture system.
private struct ChatRowLink: View {
    let chat: ChatRoom
    let currentUserId: String
    let other: UserProfile?
    let peerId: String

    var body: some View {
        NavigationLink {
            ChatThreadView(chat: chat)
        } label: {
            ChatRow(chat: chat,
                    currentUserId: currentUserId,
                    other: other,
                    peerId: peerId)
        }
    }
}

/// Standalone screen for archived chats. Same row look as the inbox, with
/// a swipe-action to unarchive (back to inbox) or fully delete.
private struct ArchivedChatsView: View {
    let chats: [ChatRoom]
    let profiles: [String: UserProfile]
    let currentUserId: String
    let onChange: () -> Void
    @EnvironmentObject private var loc: LocalizationService
    @State private var tick: Int = 0

    var body: some View {
        Group {
            if chats.isEmpty || tick < 0 /* never true; tick triggers reread */ {
                EmptyState(
                    systemImage: "archivebox",
                    title: loc.t("chats_archive_empty_title"),
                    subtitle: loc.t("chats_archive_empty_sub")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(chats.filter { !ChatsLocalState.isHidden($0.id) && ChatsLocalState.isArchived($0.id) }) { chat in
                        let otherId = chat.otherParticipantId(currentUser: currentUserId) ?? ""
                        ChatRowLink(chat: chat,
                                    currentUserId: currentUserId,
                                    other: profiles[otherId],
                                    peerId: otherId)
                            .listRowBackground(Color.white.opacity(0.04))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    ChatsLocalState.hide(chat.id)
                                    tick &+= 1
                                    onChange()
                                } label: {
                                    Label(loc.t("chats_delete"), systemImage: "trash")
                                }
                                Button {
                                    ChatsLocalState.unarchive(chat.id)
                                    tick &+= 1
                                    onChange()
                                } label: {
                                    Label(loc.t("chats_unarchive"), systemImage: "tray.and.arrow.up")
                                }
                                .tint(.indigo)
                            }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .id(tick)
            }
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .navigationTitle(loc.t("chats_archive"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct ChatRow: View {
    let chat: ChatRoom
    let currentUserId: String
    let other: UserProfile?
    let peerId: String
    @EnvironmentObject private var loc: LocalizationService

    /// Fallback name when peer profile didn't load — shorter UID prefix
    /// is more useful than a generic "User" label for distinguishing chats.
    private var displayName: String {
        if let p = other?.displayName, !p.isEmpty { return p }
        if !peerId.isEmpty { return "ID " + String(peerId.prefix(6)) }
        return loc.t("common_user")
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: other?.avatar, name: other?.displayName ?? peerId, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if other?.hasActiveVerifiedBadge == true {
                        VerifiedChip(size: 12)
                    }
                    if other?.isPro == true {
                        Text("PRO")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    if ChatsLocalState.isMuted(chat.id) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let at = chat.lastMessageAt { Text(formatRelative(at)).font(.system(size: 11)).foregroundColor(.white.opacity(0.4)) }
                let unread = chat.unreadCount(for: currentUserId)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ChatsLocalState.isMuted(chat.id) ? Color.white.opacity(0.25) : Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Last message if present, otherwise task title (so the row is never empty).
    private var preview: String {
        if let last = chat.lastMessage, !last.isEmpty { return last }
        if let task = chat.taskTitle, !task.isEmpty { return "\(loc.t("chats_task")) \(task)" }
        return loc.t("chats_no_messages")
    }

    private func formatRelative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: d, relativeTo: Date())
    }
}
