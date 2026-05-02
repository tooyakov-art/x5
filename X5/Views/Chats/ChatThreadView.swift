import SwiftUI
import PhotosUI
import AVFoundation

struct ChatThreadView: View {
    let chat: ChatRoom

    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var service = ChatsService()
    @StateObject private var recorder = AudioRecorder()
    @State private var messages: [ChatMessageRow] = []
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var other: UserProfile?
    @State private var showingProfile: Bool = false
    @State private var showingMenu: Bool = false
    @State private var confirmBlock: Bool = false
    @State private var photoItem: PhotosPickerItem?
    @State private var attachmentError: String?
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

            HStack(spacing: 8) {
                // Attach photo
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 36, height: 36)
                }

                if recorder.isRecording {
                    // Voice recording state
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("Запись… отпусти чтобы отправить")
                            .font(.system(size: 13)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.red.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    TextField(loc.t("chats_message_placeholder"), text: $draft, axis: .vertical)
                        .focused($inputFocused)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(20)
                        .lineLimit(1...4)
                }

                if canSend {
                    // Text-send button
                    Button(action: send) {
                        Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.accentColor)
                    }
                    .disabled(sending)
                } else {
                    // Press-and-hold mic
                    Image(systemName: recorder.isRecording ? "mic.circle.fill" : "mic.circle")
                        .font(.system(size: 30))
                        .foregroundColor(recorder.isRecording ? .red : .white.opacity(0.6))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !recorder.isRecording {
                                        Task { await recorder.start() }
                                    }
                                }
                                .onEnded { _ in
                                    if let result = recorder.stop() {
                                        Task { await sendVoice(result) }
                                    } else {
                                        recorder.cancel()
                                    }
                                }
                        )
                }
            }
            .padding(12)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
        }
        .background(ChatBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingProfile = true
                    } label: {
                        Label("Открыть профиль", systemImage: "person.crop.circle")
                    }
                    Divider()
                    Button {
                        report()
                    } label: {
                        Label("Пожаловаться", systemImage: "exclamationmark.bubble")
                    }
                    Button(role: .destructive) {
                        confirmBlock = true
                    } label: {
                        Label("Заблокировать", systemImage: "hand.raised.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
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
                                if other?.hasActiveVerifiedBadge == true {
                                    VerifiedChip(size: 11)
                                }
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
        .confirmationDialog(
            "Заблокировать пользователя?",
            isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button("Заблокировать", role: .destructive) { block() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сообщения от этого пользователя больше не будут показываться.")
        }
        .onChange(of: photoItem) { newValue in
            guard let newValue else { return }
            Task { await sendPhoto(newValue); photoItem = nil }
        }
        .alert("Не отправилось", isPresented: Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "")
        }
        .task {
            // Paint cached messages instantly so the chat doesn't appear
            // blank during the fetch — Telegram-style.
            let cached = service.cachedMessages(chatId: chat.id)
            if !cached.isEmpty && messages.isEmpty {
                messages = cached
            }
            await reload()
            await loadOther()
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard let token = auth.accessToken, let uid = auth.userId else { return }
        sending = true
        defer { sending = false }
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: raw),
              let jpeg = img.jpegData(compressionQuality: 0.82) else {
            attachmentError = "Не удалось прочитать фото."
            return
        }
        guard let url = await service.uploadAttachment(chatId: chat.id, data: jpeg, mime: "image/jpeg", ext: "jpg", accessToken: token) else {
            attachmentError = service.error ?? "Не удалось загрузить фото."
            return
        }
        if let inserted = await service.sendMedia(chatId: chat.id, currentUserId: uid, type: "image", mediaUrl: url, mime: "image/jpeg", accessToken: token) {
            messages.append(inserted)
        } else {
            attachmentError = service.error ?? "Не удалось отправить фото."
        }
    }

    private func sendVoice(_ result: (data: Data, mime: String, ext: String)) async {
        guard let token = auth.accessToken, let uid = auth.userId else { return }
        sending = true
        defer { sending = false }
        guard let url = await service.uploadAttachment(chatId: chat.id, data: result.data, mime: result.mime, ext: result.ext, accessToken: token) else {
            attachmentError = service.error ?? "Не удалось загрузить голосовое."
            return
        }
        if let inserted = await service.sendMedia(chatId: chat.id, currentUserId: uid, type: "audio", mediaUrl: url, mime: result.mime, accessToken: token) {
            messages.append(inserted)
        } else {
            attachmentError = service.error ?? "Не удалось отправить голосовое."
        }
    }

    private func report() {
        let otherId = chat.otherParticipantId(currentUser: auth.userId ?? "") ?? "unknown"
        let subject = "Report user \(otherId)"
        let body = "Hi X5 team,\n\nI'd like to report this user. Please review their content.\n\nUser ID: \(otherId)\nChat ID: \(chat.id)\n"
        if let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mailto:support@x5studio.app?subject=\(s)&body=\(b)") {
            UIApplication.shared.open(url)
        }
    }

    private func block() {
        guard let otherId = chat.otherParticipantId(currentUser: auth.userId ?? "") else { return }
        BlockList.add(otherId)
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
            content
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.type {
        case "image":
            imageBubble
        case "audio":
            AudioBubble(url: message.mediaUrl, isMine: isMine)
        default:
            Text(message.content ?? "")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isMine ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var imageBubble: some View {
        if let s = message.mediaUrl, let url = URL(string: s) {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.06).overlay(ProgressView().tint(.white.opacity(0.5)))
            }
            .frame(maxWidth: 240, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct AudioBubble: View {
    let url: String?
    let isMine: Bool
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            Text("Голосовое")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isMine ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func togglePlay() {
        guard let s = url, let u = URL(string: s) else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: u)
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                isPlaying = false
                player?.seek(to: .zero)
            }
        }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }
}
