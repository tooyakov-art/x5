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
    let isVerified: Bool?
    let verifiedUntil: String?
    var subscriptionEndDate: String? = nil

    var isPro: Bool {
        UserProfile.isPaidPlanActive(plan: plan, endDate: subscriptionEndDate)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, avatar, bio, plan, services
        case specialistCategory = "specialist_category"
        case socialLinks = "social_links"
        case isVerified = "is_verified"
        case verifiedUntil = "verified_until"
        case subscriptionEndDate = "subscription_end_date"
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
    let publicVisibleAt: String?
    let acceptedSpecialistId: String?
    let acceptedSpecialistName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, budget, category, deadline, status
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case companyName = "company_name"
        case createdAt = "created_at"
        case publicVisibleAt = "public_visible_at"
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
    let labelRu: String
    let labelKk: String
}

enum HubCategories {
    static let all: [HubCategory] = [
        .init(id: "marketing", emoji: "📣", labelEn: "Marketing", labelRu: "Маркетинг", labelKk: "Маркетинг"),
        .init(id: "smm", emoji: "📱", labelEn: "SMM", labelRu: "SMM", labelKk: "SMM"),
        .init(id: "targeting", emoji: "🎯", labelEn: "Ads", labelRu: "Таргет", labelKk: "Таргет"),
        .init(id: "seo", emoji: "🔍", labelEn: "SEO", labelRu: "SEO", labelKk: "SEO"),
        .init(id: "sales", emoji: "💰", labelEn: "Sales", labelRu: "Продажи", labelKk: "Сату"),
        .init(id: "design", emoji: "🎨", labelEn: "Design", labelRu: "Дизайн", labelKk: "Дизайн"),
        .init(id: "ui_ux", emoji: "📐", labelEn: "UI/UX", labelRu: "UI/UX", labelKk: "UI/UX"),
        .init(id: "motion", emoji: "✨", labelEn: "Motion", labelRu: "Моушн", labelKk: "Моушн"),
        .init(id: "3d", emoji: "🧊", labelEn: "3D / CGI", labelRu: "3D / CGI", labelKk: "3D / CGI"),
        .init(id: "web_dev", emoji: "🌐", labelEn: "Web Dev", labelRu: "Веб-разработка", labelKk: "Веб-әзірлеу"),
        .init(id: "mobile_dev", emoji: "📲", labelEn: "Mobile Dev", labelRu: "Мобильные", labelKk: "Мобильді"),
        .init(id: "bot_dev", emoji: "🤖", labelEn: "Chatbots", labelRu: "Чат-боты", labelKk: "Чат-боттар"),
        .init(id: "ai_ml", emoji: "🧠", labelEn: "AI / ML", labelRu: "AI / ML", labelKk: "AI / ML"),
        .init(id: "gamedev", emoji: "🎮", labelEn: "Game Dev", labelRu: "Геймдев", labelKk: "Геймдев"),
        .init(id: "ugc", emoji: "📹", labelEn: "UGC", labelRu: "UGC", labelKk: "UGC"),
        .init(id: "copy", emoji: "✍️", labelEn: "Copywriting", labelRu: "Копирайтинг", labelKk: "Копирайтинг"),
        .init(id: "video", emoji: "🎬", labelEn: "Video / Editing", labelRu: "Видео / монтаж", labelKk: "Видео / монтаж"),
        .init(id: "photo", emoji: "📸", labelEn: "Photo", labelRu: "Фото", labelKk: "Фото"),
        .init(id: "audio", emoji: "🎙️", labelEn: "Audio", labelRu: "Аудио", labelKk: "Аудио"),
        .init(id: "animation", emoji: "🎞️", labelEn: "Animation", labelRu: "Анимация", labelKk: "Анимация"),
        .init(id: "translation", emoji: "🌍", labelEn: "Translation", labelRu: "Перевод", labelKk: "Аударма"),
        .init(id: "consulting", emoji: "💼", labelEn: "Consulting", labelRu: "Консалтинг", labelKk: "Кеңес беру"),
        .init(id: "finance", emoji: "📊", labelEn: "Finance", labelRu: "Финансы", labelKk: "Қаржы"),
        .init(id: "legal", emoji: "⚖️", labelEn: "Legal", labelRu: "Юристы", labelKk: "Заңгерлер"),
        .init(id: "hr", emoji: "👥", labelEn: "HR", labelRu: "HR", labelKk: "HR"),
        .init(id: "education", emoji: "🎓", labelEn: "Education", labelRu: "Обучение", labelKk: "Оқыту"),
        .init(id: "assistant", emoji: "📋", labelEn: "Assistant", labelRu: "Ассистент", labelKk: "Ассистент"),
        .init(id: "other", emoji: "🔧", labelEn: "Other", labelRu: "Другое", labelKk: "Басқа")
    ]

    static func label(for id: String?) -> String {
        guard let id else { return "Other" }
        return all.first(where: { $0.id == id })?.labelEn ?? id.capitalized
    }

    static func label(for id: String?, language: AppLanguage) -> String {
        guard let id else {
            switch language {
            case .ru: return "Другое"
            case .kk: return "Басқа"
            case .en: return "Other"
            }
        }
        guard let category = all.first(where: { $0.id == id }) else { return id.capitalized }
        switch language {
        case .ru: return category.labelRu
        case .kk: return category.labelKk
        case .en: return category.labelEn
        }
    }

    static func symbol(for id: String?) -> String {
        switch id {
        case "marketing": return "megaphone.fill"
        case "smm": return "iphone"
        case "targeting": return "scope"
        case "seo": return "magnifyingglass"
        case "sales": return "dollarsign.circle.fill"
        case "design": return "paintpalette.fill"
        case "ui_ux": return "ruler"
        case "motion": return "sparkles"
        case "3d": return "cube.transparent.fill"
        case "web_dev": return "globe"
        case "mobile_dev": return "apps.iphone"
        case "bot_dev": return "cpu.fill"
        case "ai_ml": return "brain.head.profile"
        case "gamedev": return "gamecontroller.fill"
        case "ugc": return "video.fill"
        case "copy": return "pencil.and.outline"
        case "video": return "movieclapper.fill"
        case "photo": return "camera.fill"
        case "audio": return "waveform"
        case "animation": return "film.stack"
        case "translation": return "character.book.closed.fill"
        case "consulting": return "briefcase.fill"
        case "finance": return "chart.line.uptrend.xyaxis"
        case "legal": return "scalemass.fill"
        case "hr": return "person.2.fill"
        case "education": return "graduationcap.fill"
        case "assistant": return "checklist"
        default: return "wrench.and.screwdriver.fill"
        }
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
            URLQueryItem(name: "select", value: "id,name,nickname,avatar,bio,specialist_category,plan,services,social_links,is_verified,verified_until,subscription_end_date"),
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

    func loadTasks(accessToken: String? = nil) async {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/tasks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "status", value: "eq.open"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        do {
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            tasks = (try? JSONDecoder().decode([HubTask].self, from: data)) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Writes

    /// Inserts a new task. Returns the new task on success.
    @discardableResult
    func createTask(authorId: String, authorName: String?, authorAvatar: String?, companyName: String?, title: String, description: String, budget: String, category: String, deadline: Date?, accessToken: String) async -> HubTask? {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/tasks"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = [
            "author_id": authorId,
            "title": title,
            "description": description,
            "budget": budget,
            "category": category,
            "status": "open"
        ]
        if let n = authorName { body["author_name"] = n }
        if let a = authorAvatar { body["author_avatar"] = a }
        if let c = companyName, !c.isEmpty { body["company_name"] = c }
        if let d = deadline {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
            body["deadline"] = f.string(from: d)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([HubTask].self, from: data)
        else { return nil }
        let inserted = rows.first
        await loadTasks(accessToken: accessToken)
        return inserted
    }

    /// Inserts a response on a task. Returns the row on success.
    @discardableResult
    func respondToTask(taskId: String, specialistId: String, specialistName: String?, specialistAvatar: String?, message: String, accessToken: String) async -> TaskResponse? {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/task_responses"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = [
            "task_id": taskId,
            "specialist_id": specialistId,
            "message": message,
            "status": "open"
        ]
        if let n = specialistName { body["specialist_name"] = n }
        if let a = specialistAvatar { body["specialist_avatar"] = a }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([TaskResponse].self, from: data)
        else { return nil }
        return rows.first
    }

    /// Marks a response accepted and the task in_progress.
    func acceptResponse(taskId: String, responseId: String, specialistId: String, specialistName: String?, accessToken: String) async {
        // 1. Patch response status
        var rURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/task_responses"), resolvingAgainstBaseURL: false)!
        rURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(responseId)")]
        var rReq = URLRequest(url: rURL.url!)
        rReq.httpMethod = "PATCH"
        rReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        rReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        rReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        rReq.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "accepted"])
        _ = try? await URLSession.shared.data(for: rReq)

        // 2. Patch task
        var tURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/tasks"), resolvingAgainstBaseURL: false)!
        tURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(taskId)")]
        var tReq = URLRequest(url: tURL.url!)
        tReq.httpMethod = "PATCH"
        tReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        tReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        tReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "status": "in_progress",
            "accepted_response_id": responseId,
            "accepted_specialist_id": specialistId
        ]
        if let n = specialistName { body["accepted_specialist_name"] = n }
        tReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: tReq)
        await loadTasks(accessToken: accessToken)
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
