import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// Instagram-style portfolio feed. Used inside ProfileView (own) and UserProfileView (public).
struct PortfolioGrid: View {
    let userId: String
    let canEdit: Bool

    @EnvironmentObject private var auth: Auth
    @StateObject private var service = PortfolioService()
    @State private var showingAdd = false
    @State private var selectedIndex: Int?
    @State private var showingPostViewer = false
    @State private var pinnedTick = 0

    private var orderedItems: [PortfolioItem] {
        _ = pinnedTick
        let pinned = service.items.filter { PortfolioPinnedStore.isPinned($0.id) }
            .sorted { (PortfolioPinnedStore.index(of: $0.id) ?? 99) < (PortfolioPinnedStore.index(of: $1.id) ?? 99) }
        let rest = service.items.filter { !PortfolioPinnedStore.isPinned($0.id) }
        return pinned + rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Портфолио")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if canEdit {
                    Button {
                        showingAdd = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Добавить")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                    }
                }
            }

            if service.items.isEmpty && !service.isLoading {
                VStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                    Text(canEdit ? "Загрузи свои работы" : "Портфолио пустое")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                    spacing: 3
                ) {
                    ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                        PortfolioGridCell(
                            item: item,
                            isPinned: PortfolioPinnedStore.isPinned(item.id),
                            onOpen: {
                                X5Feedback.selection()
                                selectedIndex = index
                                showingPostViewer = true
                            }
                        )
                    }
                }
            }
        }
        .task {
            guard let token = auth.accessToken else { return }
            await service.load(userId: userId, accessToken: token, includeUnapproved: canEdit)
        }
        .sheet(isPresented: $showingAdd) {
            AddPortfolioItemView { data, mediaType, mime, ext, title, desc in
                guard let token = auth.accessToken else { return false }
                return await service.addMedia(data: data, type: mediaType, mime: mime, ext: ext, userId: userId, title: title, description: desc, accessToken: token)
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showingPostViewer) {
            PortfolioInstagramViewer(
                items: orderedItems,
                initialIndex: selectedIndex ?? 0,
                canEdit: canEdit,
                onDelete: { item in
                    guard let token = auth.accessToken else { return }
                    Task { await service.delete(itemId: item.id, accessToken: token) }
                    showingPostViewer = false
                },
                onTogglePin: { item in
                    PortfolioPinnedStore.toggle(item.id)
                    pinnedTick += 1
                },
                onUpdateDetails: { item, title, description in
                    guard let token = auth.accessToken else { return nil }
                    return await service.updateDetails(itemId: item.id, title: title, description: description, accessToken: token)
                },
                isPinned: { item in
                    PortfolioPinnedStore.isPinned(item.id)
                },
                onLoadLike: { item in
                    guard let token = auth.accessToken, let uid = auth.userId else {
                        return PortfolioLikeState(isLiked: false, count: 0)
                    }
                    return await service.likeState(itemId: item.id, currentUserId: uid, accessToken: token)
                },
                onSetLiked: { item, liked in
                    guard let token = auth.accessToken, let uid = auth.userId else { return false }
                    return await service.setLiked(itemId: item.id, liked: liked, currentUserId: uid, accessToken: token)
                },
                onLoadComments: { item in
                    guard let token = auth.accessToken else { return [] }
                    return await service.loadComments(itemId: item.id, accessToken: token)
                },
                onAddComment: { item, text in
                    guard let token = auth.accessToken, let uid = auth.userId else { return nil }
                    return await service.addComment(itemId: item.id,
                                                    userId: uid,
                                                    userName: auth.userEmail,
                                                    userAvatar: nil,
                                                    text: text,
                                                    accessToken: token)
                }
            )
            .preferredColorScheme(.dark)
        }
    }
}

private enum PortfolioPinnedStore {
    private static let key = "x5.portfolio.pinned.ids"

    static func ids() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func isPinned(_ id: String) -> Bool {
        ids().contains(id)
    }

    static func index(of id: String) -> Int? {
        ids().firstIndex(of: id)
    }

    static func toggle(_ id: String) {
        var current = ids()
        if let index = current.firstIndex(of: id) {
            current.remove(at: index)
        } else {
            current.insert(id, at: 0)
            current = Array(current.prefix(3))
        }
        UserDefaults.standard.set(current, forKey: key)
    }
}

private struct PortfolioGridCell: View {
    let item: PortfolioItem
    let isPinned: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Color.white.opacity(0.055)

                if item.type == "video" {
                    Color.black.opacity(0.42)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                } else if let s = imageURLString, let url = URL(string: s) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.white.opacity(0.5))
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    HStack {
                        if item.needsModerationBadge {
                            PortfolioModerationBadge(item: item)
                        }
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        Spacer()
                        if item.type == "video" {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    Spacer()
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(7)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var imageURLString: String? {
        if let thumbnail = item.thumbnailUrl, !thumbnail.isEmpty { return thumbnail }
        return item.mediaUrl
    }
}

private struct PortfolioFeedCard: View {
    let item: PortfolioItem
    let canEdit: Bool
    let isPinned: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                ZStack {
                    Color.white.opacity(0.06)
                    if item.type == "video" {
                        Color.black.opacity(0.55)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    } else if let s = item.mediaUrl, let url = URL(string: s) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(.white.opacity(0.5))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if item.needsModerationBadge {
                        PortfolioModerationBadge(item: item)
                            .padding(10)
                    } else if isPinned {
                        Label("Закреп", systemImage: "pin.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.62))
                            .lineLimit(2)
                    }
                    if item.type == "video" {
                        Label("Открыть в видео-редакторе", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                Spacer()
                if canEdit {
                    Menu {
                        Button {
                            onTogglePin()
                        } label: {
                            Label(isPinned ? "Открепить" : "Закрепить", systemImage: isPinned ? "pin.slash" : "pin")
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.82))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct PortfolioModerationBadge: View {
    let item: PortfolioItem

    var body: some View {
        Label(item.moderationBadgeTitle, systemImage: symbol)
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }

    private var symbol: String {
        switch item.moderationStatus {
        case "rejected": return "xmark.octagon.fill"
        case "manual_review": return "person.crop.circle.badge.questionmark"
        case "failed": return "exclamationmark.triangle.fill"
        default: return "clock.fill"
        }
    }

    private var foreground: Color {
        item.moderationStatus == "rejected" ? .white : .black
    }

    private var background: Color {
        switch item.moderationStatus {
        case "rejected": return .red
        case "manual_review", "failed": return .orange
        default: return .accentColor
        }
    }
}

private struct PortfolioCell: View {
    let item: PortfolioItem
    let canEdit: Bool
    let onDelete: () -> Void
    let onLoadLike: () async -> PortfolioLikeState
    let onSetLiked: (Bool) async -> Bool

    @State private var confirmDelete = false
    @State private var likeState = PortfolioLikeState(isLiked: false, count: 0)
    @State private var likeBusy = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Color.white.opacity(0.06)
                if item.type == "video" {
                    Color.black.opacity(0.55)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                } else if let s = item.mediaUrl, let url = URL(string: s) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.white.opacity(0.5))
                    }
                }
            }
            .frame(height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if canEdit {
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .padding(6)
            } else {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Label("\(likeState.count)", systemImage: likeState.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.46))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(likeBusy)
                .padding(6)
            }
        }
        .task {
            if !canEdit {
                likeState = await onLoadLike()
            }
        }
        .confirmationDialog("Удалить из портфолио?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { onDelete() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func toggleLike() async {
        guard !likeBusy else { return }
        likeBusy = true
        defer { likeBusy = false }
        let next = !likeState.isLiked
        let ok = await onSetLiked(next)
        guard ok else { return }
        likeState = PortfolioLikeState(
            isLiked: next,
            count: max(0, likeState.count + (next ? 1 : -1))
        )
    }
}

private struct PortfolioInstagramViewer: View {
    let items: [PortfolioItem]
    let initialIndex: Int
    let canEdit: Bool
    let onDelete: (PortfolioItem) -> Void
    let onTogglePin: (PortfolioItem) -> Void
    let onUpdateDetails: (PortfolioItem, String?, String?) async -> PortfolioItem?
    let isPinned: (PortfolioItem) -> Bool
    let onLoadLike: (PortfolioItem) async -> PortfolioLikeState
    let onSetLiked: (PortfolioItem, Bool) async -> Bool
    let onLoadComments: (PortfolioItem) async -> [PortfolioComment]
    let onAddComment: (PortfolioItem, String) async -> PortfolioComment?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            PortfolioInstagramPostPage(
                                item: item,
                                canEdit: canEdit,
                                isPinned: isPinned(item),
                                onDelete: { onDelete(item) },
                                onTogglePin: { onTogglePin(item) },
                                onUpdateDetails: { title, description in await onUpdateDetails(item, title, description) },
                                onLoadLike: { await onLoadLike(item) },
                                onSetLiked: { liked in await onSetLiked(item, liked) },
                                onLoadComments: { await onLoadComments(item) },
                                onAddComment: { text in await onAddComment(item, text) }
                            )
                            .id(item.id)
                            .frame(width: UIScreen.main.bounds.width)
                            .frame(minHeight: UIScreen.main.bounds.height)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(Color.black)
                .onAppear {
                    guard items.indices.contains(initialIndex) else { return }
                    proxy.scrollTo(items[initialIndex].id, anchor: .top)
                }
            }
            .navigationTitle("Портфолио")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") {
                        X5Feedback.selection()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PortfolioInstagramPostPage: View {
    let item: PortfolioItem
    let canEdit: Bool
    let isPinned: Bool
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onUpdateDetails: (String?, String?) async -> PortfolioItem?
    let onLoadLike: () async -> PortfolioLikeState
    let onSetLiked: (Bool) async -> Bool
    let onLoadComments: () async -> [PortfolioComment]
    let onAddComment: (String) async -> PortfolioComment?

    @State private var likeState = PortfolioLikeState(isLiked: false, count: 0)
    @State private var comments: [PortfolioComment] = []
    @State private var commentDraft = ""
    @State private var busyLike = false
    @State private var sendingComment = false
    @State private var isSaved = false
    @State private var confirmDelete = false
    @State private var showingEdit = false
    @State private var showVideoEditorNotice = false
    @State private var localLikedComments: Set<String> = []
    @State private var player: AVPlayer?

    private var maxMediaHeight: CGFloat {
        let screen = UIScreen.main.bounds
        return min(screen.width * 1.06, screen.height * 0.54)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            media
                .frame(maxWidth: .infinity)
                .frame(height: maxMediaHeight)
                .background(Color.white.opacity(0.04))
                .clipped()

            VStack(alignment: .leading, spacing: 12) {
                actionRow
                captionBlock
                commentsView
                commentInput
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(Color.black)
        .task {
            likeState = await onLoadLike()
            comments = await onLoadComments()
            if item.type == "video", let s = item.mediaUrl, let url = URL(string: s) {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .confirmationDialog("Удалить кейс?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                X5Feedback.warning()
                onDelete()
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Video editor", isPresented: $showVideoEditorNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Монтаж видео будет открыт для этого кейса.")
        }
        .sheet(isPresented: $showingEdit) {
            EditPortfolioItemView(item: item, onSave: onUpdateDetails)
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var media: some View {
        if item.type == "video", let player {
            VideoPlayer(player: player)
        } else if let s = item.mediaUrl, let url = URL(string: s) {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button {
                Task { await toggleLike() }
            } label: {
                Image(systemName: likeState.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(likeState.isLiked ? Color.red : Color.white)
            }
            .disabled(busyLike)

            Image(systemName: "bubble.right")

            ShareLink(item: item.mediaUrl ?? "") {
                Image(systemName: "paperplane")
            }

            Spacer()

            Button {
                isSaved.toggle()
                X5Feedback.selection()
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }

            if canEdit {
                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }

                Menu {
                    Button {
                        X5Feedback.selection()
                        onTogglePin()
                    } label: {
                        Label(isPinned ? "Открепить" : "Закрепить", systemImage: isPinned ? "pin.slash" : "pin")
                    }
                    if item.type == "video" {
                        Button {
                            showVideoEditorNotice = true
                        } label: {
                            Label("Монтаж видео", systemImage: "wand.and.stars")
                        }
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .font(.system(size: 25, weight: .semibold))
        .foregroundColor(.white)
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if item.needsModerationBadge {
                VStack(alignment: .leading, spacing: 4) {
                    PortfolioModerationBadge(item: item)
                    Text(item.moderationReason?.isEmpty == false ? item.moderationReason! : "Пока не показывается в публичном Hub.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.62))
                }
                .padding(.bottom, 4)
            }
            if likeState.count > 0 {
                Text("\(likeState.count) отметок \"Нравится\"")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
            }
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.82))
            }
            if item.type == "video", canEdit {
                Button {
                    showVideoEditorNotice = true
                } label: {
                    Label("Открыть монтаж видео", systemImage: "wand.and.stars")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white)
            }
        }
    }

    private var commentsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if comments.count > 4 {
                Text("Посмотреть все комментарии: \(comments.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.52))
            }
            ForEach(comments.prefix(6)) { comment in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.userName?.isEmpty == false ? comment.userName! : "X Five Marketing")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.65))
                        Text(comment.text)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        HStack(spacing: 12) {
                            Button("Ответить") {
                                commentDraft = "@\(comment.userName?.isEmpty == false ? comment.userName! : "xfive") "
                            }
                            Button(localLikedComments.contains(comment.id) ? "Нравится" : "Лайк") {
                                if localLikedComments.contains(comment.id) {
                                    localLikedComments.remove(comment.id)
                                } else {
                                    localLikedComments.insert(comment.id)
                                }
                                X5Feedback.selection()
                            }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.48))
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commentInput: some View {
        HStack(spacing: 8) {
            TextField("Комментарий...", text: $commentDraft)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: sendingComment ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendingComment)
        }
        .foregroundColor(.accentColor)
    }

    private func toggleLike() async {
        guard !busyLike else { return }
        busyLike = true
        defer { busyLike = false }
        let next = !likeState.isLiked
        X5Feedback.selection()
        guard await onSetLiked(next) else { return }
        likeState = PortfolioLikeState(isLiked: next, count: max(0, likeState.count + (next ? 1 : -1)))
    }

    private func sendComment() async {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sendingComment else { return }
        sendingComment = true
        defer { sendingComment = false }
        if let comment = await onAddComment(text) {
            comments.append(comment)
            commentDraft = ""
            X5Feedback.success()
        }
    }
}

private struct PortfolioPostViewer: View {
    let item: PortfolioItem
    let canEdit: Bool
    let onDelete: () -> Void
    let onLoadLike: () async -> PortfolioLikeState
    let onSetLiked: (Bool) async -> Bool
    let onLoadComments: () async -> [PortfolioComment]
    let onAddComment: (String) async -> PortfolioComment?

    @Environment(\.dismiss) private var dismiss
    @State private var likeState = PortfolioLikeState(isLiked: false, count: 0)
    @State private var comments: [PortfolioComment] = []
    @State private var commentDraft = ""
    @State private var busyLike = false
    @State private var sendingComment = false
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView {
                    postPage
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(item.title?.isEmpty == false ? item.title! : "Пост")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { onDelete() } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .task {
                likeState = await onLoadLike()
                comments = await onLoadComments()
                if item.type == "video", let s = item.mediaUrl, let url = URL(string: s) {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    private var postPage: some View {
        VStack(spacing: 0) {
            media
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                actionRow
                commentsView
                commentInput
            }
            .padding(14)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var media: some View {
        if item.type == "video", let player {
            VideoPlayer(player: player)
        } else if let s = item.mediaUrl, let url = URL(string: s) {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .padding(.horizontal, 10)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 18) {
            Button {
                Task { await toggleLike() }
            } label: {
                Label("\(likeState.count)", systemImage: likeState.isLiked ? "heart.fill" : "heart")
            }
            .disabled(busyLike)

            Label("\(comments.count)", systemImage: "text.bubble")

            ShareLink(item: item.mediaUrl ?? "") {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }

            Spacer()
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.white)
    }

    private var commentsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(comments.prefix(4)) { comment in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.userName?.isEmpty == false ? comment.userName! : "X Five Marketing")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.65))
                        Text(comment.text)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commentInput: some View {
        HStack(spacing: 8) {
            TextField("Комментарий...", text: $commentDraft)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: sendingComment ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendingComment)
        }
        .foregroundColor(.accentColor)
    }

    private func toggleLike() async {
        guard !busyLike else { return }
        busyLike = true
        defer { busyLike = false }
        let next = !likeState.isLiked
        guard await onSetLiked(next) else { return }
        likeState = PortfolioLikeState(isLiked: next, count: max(0, likeState.count + (next ? 1 : -1)))
    }

    private func sendComment() async {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sendingComment else { return }
        sendingComment = true
        defer { sendingComment = false }
        if let comment = await onAddComment(text) {
            comments.append(comment)
            commentDraft = ""
        }
    }
}

private struct EditPortfolioItemView: View {
    let item: PortfolioItem
    let onSave: (String?, String?) async -> PortfolioItem?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var saving = false
    @State private var errorText: String?

    init(item: PortfolioItem, onSave: @escaping (String?, String?) async -> PortfolioItem?) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title ?? "")
        _description = State(initialValue: item.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Кейс") {
                    TextField("Название", text: $title)
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(3...7)
                }
                if item.type == "video" {
                    Section {
                        Label("Видео можно отправить в монтаж из меню поста.", systemImage: "wand.and.stars")
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundColor(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Сохранить").bold() }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if await onSave(cleanTitle.isEmpty ? nil : cleanTitle,
                        cleanDescription.isEmpty ? nil : cleanDescription) != nil {
            X5Feedback.success()
            dismiss()
        } else {
            X5Feedback.error()
            errorText = "Не удалось сохранить."
        }
    }
}

// MARK: - Add item

struct AddPortfolioItemView: View {
    let onSave: (Data, String, String, String, String?, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var mediaItem: PhotosPickerItem?
    @State private var mediaData: Data?
    @State private var mediaType: String = "image"
    @State private var mime: String = "image/jpeg"
    @State private var ext: String = "jpg"
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $mediaItem, matching: .any(of: [.images, .videos])) {
                        if mediaType == "video", mediaData != nil {
                            VStack(spacing: 10) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 44, weight: .semibold))
                                Text("Видео выбрано")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 160)
                        } else if let data = mediaData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Выбрать фото или видео")
                            }
                            .frame(maxWidth: .infinity, minHeight: 100)
                        }
                    }
                    .onChange(of: mediaItem) { newValue in
                        Task { await loadMedia(newValue) }
                    }
                }

                Section("Описание") {
                    TextField("Название (опц.)", text: $title)
                    TextField("Кейс / описание (опц.)", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let err = errorText {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Добавить в портфолио")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Сохранить").bold() }
                    }
                    .disabled(saving || mediaData == nil)
                }
            }
        }
    }

    private func save() async {
        guard let data = mediaData else { return }
        saving = true
        defer { saving = false }
        let titleTrim = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let descTrim = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await onSave(data, mediaType, mime, ext, titleTrim.isEmpty ? nil : titleTrim,
                              descTrim.isEmpty ? nil : descTrim)
        if ok {
            dismiss()
        } else {
            errorText = "Не удалось сохранить. Попробуй ещё раз."
        }
    }

    /// Re-encode picked image as JPEG ≤1.5MB to keep uploads fast.
    private func compress(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1600
        let s = image.size
        let scale = min(maxSide / max(s.width, s.height), 1)
        let target = CGSize(width: s.width * scale, height: s.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }

    private func loadMedia(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        let contentType = item.supportedContentTypes.first
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
            mediaType = "video"
            mime = contentType?.preferredMIMEType ?? "video/quicktime"
            ext = contentType?.preferredFilenameExtension ?? "mov"
            mediaData = data
        } else {
            mediaType = "image"
            mime = "image/jpeg"
            ext = "jpg"
            mediaData = compress(data)
        }
    }
}
