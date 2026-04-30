import SwiftUI

/// List of all chats for the current user.
struct ChatsListView: View {
    @EnvironmentObject private var auth: Auth
    @StateObject private var service = ChatsService()

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.chats.isEmpty {
                    ProgressView().tint(.accentColor).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.chats.isEmpty {
                    EmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: "No conversations yet",
                        subtitle: "Tap a specialist in Hub and start a chat."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(service.chats) { chat in
                            NavigationLink {
                                ChatThreadView(chat: chat)
                            } label: {
                                ChatRow(chat: chat, currentUserId: auth.userId ?? "")
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
            .navigationTitle("Chats")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await reload() }
        }
    }

    private func reload() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        await service.loadChats(currentUserId: uid, accessToken: token)
    }
}

private struct ChatRow: View {
    let chat: ChatRoom
    let currentUserId: String

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: nil, name: nil, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.taskTitle ?? "Conversation")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(chat.lastMessage ?? "(no messages)")
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

    private func formatRelative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: d, relativeTo: Date())
    }
}
