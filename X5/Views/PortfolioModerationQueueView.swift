import SwiftUI
import AVKit

struct PortfolioModerationQueueView: View {
    @EnvironmentObject private var auth: Auth
    @StateObject private var service = PortfolioModerationQueueService()
    @State private var busyItemId: String?
    @State private var previewItem: PortfolioItem?

    private var hasLocalDeveloperAccess: Bool {
        Roles.isDeveloper(email: auth.userEmail, userId: auth.userId)
    }

    var body: some View {
        Group {
            if !hasLocalDeveloperAccess {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                    Text("Нет доступа")
                        .font(.headline)
                    Text("Очередь доступна только двум аккаунтам разработчиков.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if service.isLoading && service.items.isEmpty {
                ProgressView("Загружаем очередь…")
            } else if service.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Очередь пуста")
                        .font(.headline)
                    Text("Безопасные публикации одобряются автоматически.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List(service.items) { item in
                    moderationRow(item)
                }
                .refreshable {
                    await load()
                }
            }
        }
        .navigationTitle("Проверка портфолио")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(service.isLoading)
            }
        }
        .task {
            guard hasLocalDeveloperAccess else { return }
            await load()
        }
        .alert(
            "Не удалось выполнить действие",
            isPresented: Binding(
                get: { service.error != nil },
                set: { if !$0 { service.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(service.error ?? "")
        }
        .sheet(item: $previewItem) { item in
            PortfolioModerationPreviewView(item: item)
        }
    }

    @ViewBuilder
    private func moderationRow(_ item: PortfolioItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                preview(for: item)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                         ? item.title!
                         : "Без названия")
                        .font(.headline)
                    Text(item.type == "video" ? "Видео" : "Изображение")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.moderationReason ?? item.moderationBadgeTitle)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                    if let description = item.description,
                       !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(description.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    Text("Автор: \(item.userId)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button {
                previewItem = item
            } label: {
                Label(
                    item.type == "video" ? "Открыть и проиграть оригинал" : "Открыть оригинал",
                    systemImage: item.type == "video" ? "play.rectangle" : "photo"
                )
            }

            HStack {
                Button {
                    run("approve", for: item)
                } label: {
                    Label("Одобрить", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)

                Button {
                    run("reject", for: item)
                } label: {
                    Label("Отклонить", systemImage: "xmark.circle.fill")
                }
                .tint(.red)

                Button {
                    run("retry", for: item)
                } label: {
                    Label("Проверить снова", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .disabled(busyItemId != nil)

            if busyItemId == item.id {
                ProgressView("Обновляем…")
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func preview(for item: PortfolioItem) -> some View {
        if let url = trustedPortfolioImageURL(item) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color.secondary.opacity(0.16)
                    ProgressView()
                }
            }
        } else {
            ZStack {
                Color.secondary.opacity(0.16)
                Image(systemName: item.type == "video" ? "video.fill" : "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        guard let token = await auth.freshAccessToken() else { return }
        await service.load(accessToken: token)
    }

    private func run(_ action: String, for item: PortfolioItem) {
        busyItemId = item.id
        Task {
            defer { busyItemId = nil }
            guard let token = await auth.freshAccessToken() else { return }
            _ = await service.perform(
                action: action,
                itemId: item.id,
                moderationRevision: item.moderationRevision,
                accessToken: token
            )
        }
    }
}

private struct PortfolioModerationPreviewView: View {
    let item: PortfolioItem

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                originalMedia
            }
            .navigationTitle(item.title?.isEmpty == false ? item.title! : "Оригинал")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                guard item.type == "video",
                      let url = trustedPortfolioMediaURL(item.mediaUrl, ownerId: item.userId)
                else { return }
                player = AVPlayer(url: url)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var originalMedia: some View {
        if item.type == "video" {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                    .tint(.white)
            }
        } else if let url = trustedPortfolioMediaURL(item.mediaUrl, ownerId: item.userId) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
        } else {
            Label("Оригинал недоступен", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

private func trustedPortfolioImageURL(_ item: PortfolioItem) -> URL? {
    if let thumbnail = trustedPortfolioMediaURL(item.thumbnailUrl, ownerId: item.userId) {
        return thumbnail
    }
    guard item.type == "image" else { return nil }
    return trustedPortfolioMediaURL(item.mediaUrl, ownerId: item.userId)
}

private func trustedPortfolioMediaURL(_ value: String?, ownerId: String) -> URL? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty,
          var components = URLComponents(string: value),
          let expected = URLComponents(
            url: X5Config.supabaseBaseURL,
            resolvingAgainstBaseURL: false
          ),
          components.scheme == expected.scheme,
          components.host == expected.host,
          components.port == expected.port,
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil
    else {
        return nil
    }

    let marker = "/storage/v1/object/public/portfolio/"
    guard components.percentEncodedPath.hasPrefix(marker),
          let decodedPath = components.percentEncodedPath.removingPercentEncoding,
          !decodedPath.contains("\\")
    else {
        return nil
    }

    let objectPath = String(decodedPath.dropFirst(marker.count))
    let segments = objectPath.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count >= 2,
          segments.first == Substring(ownerId),
          segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else {
        return nil
    }

    components.path = decodedPath
    return components.url
}
