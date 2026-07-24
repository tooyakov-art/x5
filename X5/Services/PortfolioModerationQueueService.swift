import Foundation

@MainActor
final class PortfolioModerationQueueService: ObservableObject {
    @Published private(set) var items: [PortfolioItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }
    private var functionsBaseURL: URL {
        URL(string: "https://afwznqjpshybmqhlewmy.functions.supabase.co") ?? baseURL
    }

    func clearError() {
        error = nil
    }

    func load(accessToken: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/portfolio_items"),
            resolvingAgainstBaseURL: false
        ) else {
            error = "Не удалось открыть очередь."
            return
        }
        components.queryItems = [
            URLQueryItem(name: "moderation_status", value: "in.(pending,manual_review,failed)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        guard let url = components.url else {
            error = "Не удалось открыть очередь."
            return
        }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([PortfolioItem].self, from: data)
        else {
            error = "Очередь недоступна или у аккаунта нет прав."
            return
        }
        items = rows
    }

    func perform(
        action: String,
        itemId: String,
        moderationRevision: Int64?,
        accessToken: String
    ) async -> Bool {
        switch action {
        case "approve", "reject", "retry":
            break
        default:
            return false
        }
        guard let moderationRevision else {
            error = "Публикация изменилась. Обнови очередь."
            return false
        }

        error = nil
        var request = URLRequest(url: functionsBaseURL.appendingPathComponent("moderate-portfolio"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            PortfolioModerationActionRequest(
                itemId: itemId,
                action: action,
                moderationRevision: moderationRevision
            )
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let result = try? JSONDecoder().decode(PortfolioModerationQueueResponse.self, from: data),
              let item = result.item
        else {
            error = "Действие не выполнено. Проверь доступ и повтори."
            return false
        }

        if ["pending", "manual_review", "failed"].contains(item.moderationStatus) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            }
        } else {
            items.removeAll { $0.id == item.id }
        }
        return true
    }
}

private struct PortfolioModerationActionRequest: Encodable {
    let itemId: String
    let action: String
    let moderationRevision: Int64

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case action
        case moderationRevision = "moderation_revision"
    }
}

private struct PortfolioModerationQueueResponse: Codable {
    let item: PortfolioItem?
}
