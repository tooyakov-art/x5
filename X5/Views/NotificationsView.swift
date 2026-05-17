import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = NotificationsService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea()
                content
            }
            .navigationTitle(loc.t("notif_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("btn_done")) { dismiss() }
                }
            }
            .task { await reload() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if service.items.isEmpty && !service.isLoading {
            emptyState
        } else {
            List {
                ForEach(service.items) { item in
                    NotificationRow(item: item)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.08))
                        .task { await markRead(item) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await reload() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.white.opacity(0.4))
            Text(loc.t("notif_empty"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text(loc.t("notif_empty_desc"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func reload() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        await service.load(userId: uid, accessToken: token)
    }

    private func markRead(_ item: AppNotification) async {
        guard let token = auth.accessToken else { return }
        await service.markRead(item, accessToken: token)
    }
}

private struct NotificationRow: View {
    let item: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(item.isRead ? Color.white.opacity(0.08) : X5Style.blue.opacity(0.95))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if let time = relativeTime(item.createdAt) {
                        Text(time)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.42))
                    }
                }
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch item.type {
        case "portfolio_like": return "heart.fill"
        case "followed_user_posted": return "person.crop.circle.badge.plus"
        case "message": return "message.fill"
        default: return "bell.fill"
        }
    }

    private func relativeTime(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
