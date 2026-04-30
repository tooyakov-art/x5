import SwiftUI

struct ChatThreadView: View {
    let chat: ChatRoom

    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var service = ChatsService()
    @State private var messages: [ChatMessageRow] = []
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var other: UserProfile?
    @State private var showingProfile: Bool = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            Bubble(message: msg, isMine: msg.senderId == auth.userId)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(loc.t("chats_message_placeholder"), text: $draft, axis: .vertical)
                    .focused($inputFocused)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(20)
                    .lineLimit(1...4)
                Button(action: send) {
                    Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? .accentColor : .white.opacity(0.2))
                }
                .disabled(!canSend || sending)
            }
            .padding(12)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Telegram-style: avatar + name in nav bar, tappable → opens profile
            ToolbarItem(placement: .principal) {
                Button { showingProfile = true } label: {
                    HStack(spacing: 8) {
                        AvatarView(urlString: other?.avatar, name: other?.displayName, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(other?.displayName ?? loc.t("chats_title"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                if other?.isPro == true {
                                    Text("PRO")
                                        .font(.system(size: 8, weight: .heavy))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                            if let task = chat.taskTitle, !task.isEmpty {
                                Text(task)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            } else {
                                Text(loc.t("chats_view_profile"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(isPresented: $showingProfile) {
            let otherId = chat.otherParticipantId(currentUser: auth.userId ?? "") ?? ""
            UserProfileView(userId: otherId, fallback: nil)
        }
        .task {
            await reload()
            await loadOther()
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reload() async {
        guard let token = auth.accessToken else { return }
        messages = await service.loadMessages(chatId: chat.id, accessToken: token)
    }

    private func loadOther() async {
        guard let token = auth.accessToken,
              let myId = auth.userId,
              let otherId = chat.otherParticipantId(currentUser: myId)
        else { return }
        other = await service.loadPublicProfile(userId: otherId, accessToken: token)
    }

    private func send() {
        guard let token = auth.accessToken, let uid = auth.userId else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        inputFocused = false
        sending = true
        Task {
            if let inserted = await service.sendText(chatId: chat.id, currentUserId: uid, text: text, accessToken: token) {
                messages.append(inserted)
            }
            sending = false
        }
    }
}

private struct Bubble: View {
    let message: ChatMessageRow
    let isMine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.content ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isMine ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }
}
