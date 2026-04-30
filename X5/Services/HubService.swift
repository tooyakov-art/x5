import Foundation

// MARK: - Models

struct HubSpecialist: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let nickname: String?
    let avatar: String?
    let bio: String?
    let specialistCategory: [String]?
    let plan: String?
    let services: [String]?
    let socialLinks: SocialLinks?

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, avatar, bio, plan, services
        case specialistCategory = "specialist_category"
        case socialLinks = "social_links"
    }
}

struct HubTask: Codable, Identifiable, Hashable {
    let id: String
    let authorId: String
    let authorName: String?
    let authorAvatar: String?
    let companyName: String?
    let title: String
    let description: String?
    let budget: String?
    let category: String?
    let deadline: String?
    let status: String
    let createdAt: String?
    let acceptedSpecialistId: String?
    let acceptedSpecialistName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, budget, category, deadline, status
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case companyName = "company_name"
        case createdAt = "created_at"
        case acceptedSpecialistId = "accepted_specialist_id"
        case acceptedSpecialistName = "accepted_specialist_name"
    }
}

struct TaskResponse: Codable, Identifiable, Hashable {
    let id: String
    let taskId: String
    let specialistId: String
    let specialistName: String?
    let specialistAvatar: String?
    let message: String?
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, message, status
        case taskId = "task_id"
        case specialistId = "specialist_id"
        case specialistName = "specialist_name"
        case specialistAvatar = "specialist_avatar"
        case createdAt = "created_at"
    }
}

// MARK: - Categories (mirrors web HireView 27 categories)

struct HubCategory: Identifiable, Hashable {
    let id: String
    let emoji: String
    let labelEn: String
}

enum HubCategories {
    static let all: [HubCategory] = [
        .init(id: "marketing", emoji: "📣", labelEn: "Marketing"),
        .init(id: "smm", emoji: "📱", labelEn: "SMM"),
        .init(id: "targeting", emoji: "🎯", labelEn: "Ads"),
        .init(id: "seo", emoji: "🔍", labelEn: "SEO"),
        .init(id: "sales", emoji: "💰", labelEn: "Sales"),
        .init(id: "design", emoji: "🎨", labelEn: "Design"),
        .init(id: "ui_ux", emoji: "📐", labelEn: "UI/UX"),
        .init(id: "motion", emoji: "✨", labelEn: "Motion"),
        .init(id: "3d", emoji: "🧊", labelEn: "3D / CGI"),
        .init(id: "web_dev", emoji: "🌐", labelEn: "Web Dev"),
        .init(id: "mobile_dev", emoji: "📲", labelEn: "Mobile Dev"),
        .init(id: "bot_dev", emoji: "🤖", labelEn: "Chatbots"),
        .init(id: "ai_ml", emoji: "🧠", labelEn: "AI / ML"),
        .init(id: "gamedev", emoji: "🎮", labelEn: "Game Dev"),
        .init(id: "ugc", emoji: "📹", labelEn: "UGC"),
        .init(id: "copy", emoji: "✍️", labelEn: "Copywriting"),
        .init(id: "video", emoji: "🎬", labelEn: "Video / Editing"),
        .init(id: "photo", emoji: "📸", labelEn: "Photo"),
        .init(id: "audio", emoji: "🎙️", labelEn: "Audio"),
        .init(id: "animation", emoji: "🎞️", labelEn: "Animation"),
        .init(id: "translation", emoji: "🌍", labelEn: "Translation"),
        .init(id: "consulting", emoji: "💼", labelEn: "Consulting"),
        .init(id: "finance", emoji: "📊", labelEn: "Finance"),
        .init(id: "legal", emoji: "⚖️", labelEn: "Legal"),
        .init(id: "hr", emoji: "👥", labelEn: "HR"),
        .init(id: "education", emoji: "🎓", labelEn: "Education"),
        .init(id: "assistant", emoji: "📋", labelEn: "Assistant"),
        .init(id: "other", emoji: "🔧", labelEn: "Other")
    ]

    static func label(for id: String?) -> String {
        guard let id else { return "Other" }
        return all.first(where: { $0.id == id })?.labelEn ?? id.capitalized
    }
}

// MARK: - Service

@MainActor
final class HubService: ObservableObject {
    @Published private(set) var specialists: [HubSpecialist] = []
    @Published private(set) var tasks: [HubTask] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    func loadSpecialists() async {
        isLoading = true
        defer { isLoading = false }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,name,nickname,avatar,bio,specialist_category,plan,services,social_links"),
            URLQueryItem(name: "show_in_hub", value: "eq.true"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        do {
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            let (data, _) = try await URLSession.shared.data(for: request)
            specialists = (try? JSONDecoder().decode([HubSpecialist].self, from: data)) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadTasks() async {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/tasks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "status", value: "eq.open"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        do {
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            let (data, _) = try await URLSession.shared.data(for: request)
            tasks = (try? JSONDecoder().decode([HubTask].self, from: data)) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadResponses(taskId: String) async -> [TaskResponse] {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/task_responses"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "task_id", value: "eq.\(taskId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        do {
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            let (data, _) = try await URLSession.shared.data(for: request)
            return (try? JSONDecoder().decode([TaskResponse].self, from: data)) ?? []
        } catch {
            return []
        }
    }
}
