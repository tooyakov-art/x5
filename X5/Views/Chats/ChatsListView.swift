import SwiftUI

/// List of all chats for the current user.
struct ChatsListView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var service = ChatsService()
    @State private var profiles: [String: UserProfile] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.chats.isEmpty {
                    ProgressView().tint(.accentColor).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.chats.isEmpty {
                    EmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: loc.t("chats_empty_title"),
                        subtitle: loc.t("chats_empty_sub")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(visibleChats) { chat in
                            let otherId = chat.otherParticipantId(currentUser: auth.userId ?? "") ?? ""
                            NavigationLink {
                                ChatThreadView(chat: chat)
                            } label: {
                                ChatRow(chat: chat,
                                        currentUserId: auth.userId ?? "",
                                        other: profiles[otherId])
                            }
                            .listRowBackground(Color.white.opacity(0.04))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle(loc.t("chats_title"))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await reload() }
        }
    }

    private var visibleChats: [ChatRoom] {
        let me = auth.userId ?? ""
        return service.chats.filter { chat in
            guard let otherId = chat.otherParticipantId(currentUser: me) else { return true }
            return !BlockList.contains(otherId)
        }
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

private struct ChatRow: View {
    let chat: ChatRoom
    let currentUserId: String
    let other: UserProfile?
    @EnvironmentObject private var loc: LocalizationService

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: other?.avatar, name: other?.displayName, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(other?.displayName ?? loc.t("common_user"))
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
                        .background(Color.accentColor)
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
