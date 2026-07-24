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

    var hasActiveVerifiedBadge: Bool {
        hasActiveVerifiedBadge(at: Date())
    }

    func hasActiveVerifiedBadge(at now: Date) -> Bool {
        UserProfile.isVerifiedBadgeActive(
            isVerified: isVerified,
            until: verifiedUntil,
            now: now
        )
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

    static var hubDisplayOrder: [HubCategory] {
        var categories = all
        guard let seoIndex = categories.firstIndex(where: { $0.id == "seo" }),
              let ugcIndex = categories.firstIndex(where: { $0.id == "ugc" })
        else { return categories }
        categories.swapAt(seoIndex, ugcIndex)
        return categories
    }

    private static let validCategoryIds = Set(all.map(\.id))

    private static let profileCategoryAliases: [String: [String]] = [
        "marketer": ["marketing"],
        "marketing_specialist": ["marketing"],
        "smm_specialist": ["smm"],
        "ads": ["targeting"],
        "target": ["targeting"],
        "target_ads": ["targeting"],
        "targeting_ads": ["targeting"],
        "designer": ["design"],
        "uiux": ["ui_ux"],
        "ux_ui": ["ui_ux"],
        "web": ["web_dev"],
        "webdev": ["web_dev"],
        "web_development": ["web_dev"],
        "mobile": ["mobile_dev"],
        "mobiledev": ["mobile_dev"],
        "mobile_development": ["mobile_dev"],
        "chatbot": ["bot_dev"],
        "chatbots": ["bot_dev"],
        "botdev": ["bot_dev"],
        "ai": ["ai_ml"],
        "ml": ["ai_ml"],
        "ai_neural": ["ai_ml"],
        "game": ["gamedev"],
        "game_dev": ["gamedev"],
        "copywriting": ["copy"],
        "content": ["copy", "ugc"],
        "context_ads": ["targeting"],
        "branding": ["design"],
        "analytics": ["consulting"],
        "email": ["marketing"],
        "influence": ["ugc"],
        "strategy": ["consulting"],
        "pr": ["marketing"]
    ]

    static func normalizedIDs(from values: [String]?) -> Set<String> {
        var result: Set<String> = []

        for value in values ?? [] {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            guard !normalized.isEmpty else { continue }
            if validCategoryIds.contains(normalized) {
                result.insert(normalized)
                continue
            }

            for categoryId in profileCategoryAliases[normalized] ?? []
            where validCategoryIds.contains(categoryId) {
                result.insert(categoryId)
            }
        }

        return result
    }

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
    @Published private(set) var myTasks: [HubTask] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let session: URLSession
    private let baseURL: URL
    private let anonKey: String

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!,
        anonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"
    ) {
        self.session = session
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

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

    // MARK: - Owner task management

    /// Loads every task owned by the signed-in author, including inactive and
    /// completed rows. The explicit owner filter complements server-side RLS.
    @discardableResult
    func loadMyTasks(authorId: String, accessToken: String) async -> [HubTask] {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let request = try makeOwnedTaskRequest(
                method: "GET",
                authorId: authorId,
                accessToken: accessToken,
                extraQueryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "created_at.desc")
                ]
            )
            let rows = try await taskRows(for: request)
            myTasks = rows
            return rows
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    /// Updates an existing owned row. This deliberately uses PATCH, never the
    /// create-task POST path, so editing cannot duplicate a task.
    @discardableResult
    func updateTask(
        taskId: String,
        authorId: String,
        title: String,
        description: String,
        budget: String,
        category: String,
        deadline: Date?,
        accessToken: String
    ) async -> HubTask? {
        var body: [String: Any] = [
            "title": title,
            "description": description,
            "budget": budget,
            "category": category,
            "deadline": NSNull()
        ]
        if let deadline {
            body["deadline"] = Self.iso8601String(from: deadline)
        }

        return await mutateOwnedTask(
            method: "PATCH",
            taskId: taskId,
            authorId: authorId,
            body: body,
            accessToken: accessToken
        )
    }

    /// Changes only the publication state exposed by the owner UI.
    @discardableResult
    func setTaskActive(
        taskId: String,
        authorId: String,
        isActive: Bool,
        accessToken: String
    ) async -> HubTask? {
        let expectedStatus = isActive ? "cancelled" : "open"
        return await mutateOwnedTask(
            method: "PATCH",
            taskId: taskId,
            authorId: authorId,
            body: ["status": isActive ? "open" : "cancelled"],
            accessToken: accessToken,
            expectedStatus: expectedStatus
        )
    }

    /// Deletes only when PostgREST returns the exact owned row. A successful
    /// HTTP response with an empty body means RLS or the filters matched none.
    @discardableResult
    func deleteTask(
        taskId: String,
        authorId: String,
        accessToken: String
    ) async -> Bool {
        error = nil
        do {
            let request = try makeOwnedTaskRequest(
                method: "DELETE",
                authorId: authorId,
                taskId: taskId,
                accessToken: accessToken,
                returnRepresentation: true
            )
            let rows = try await taskRows(for: request)
            guard rows.contains(where: { $0.id == taskId && $0.authorId == authorId }) else {
                return false
            }
            myTasks.removeAll(where: { $0.id == taskId })
            return true
        } catch {
            self.error = error.localizedDescription
            return false
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

    private func mutateOwnedTask(
        method: String,
        taskId: String,
        authorId: String,
        body: [String: Any],
        accessToken: String,
        expectedStatus: String? = nil
    ) async -> HubTask? {
        error = nil
        do {
            let request = try makeOwnedTaskRequest(
                method: method,
                authorId: authorId,
                taskId: taskId,
                accessToken: accessToken,
                extraQueryItems: expectedStatus.map {
                    [URLQueryItem(name: "status", value: "eq.\($0)")]
                } ?? [],
                body: body,
                returnRepresentation: true
            )
            let rows = try await taskRows(for: request)
            guard let task = rows.first(where: {
                $0.id == taskId && $0.authorId == authorId
            }) else { return nil }
            replaceManagedTask(task)
            return task
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func makeOwnedTaskRequest(
        method: String,
        authorId: String,
        taskId: String? = nil,
        accessToken: String,
        extraQueryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        returnRepresentation: Bool = false
    ) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/tasks"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "author_id", value: "eq.\(authorId)")]
        if let taskId {
            queryItems.append(URLQueryItem(name: "id", value: "eq.\(taskId)"))
        }
        queryItems.append(contentsOf: extraQueryItems)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw HubTaskServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if returnRepresentation {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func taskRows(for request: URLRequest) async throws -> [HubTask] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HubTaskServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HubTaskServiceError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode([HubTask].self, from: data)
    }

    private func replaceManagedTask(_ task: HubTask) {
        if let index = myTasks.firstIndex(where: { $0.id == task.id }) {
            myTasks[index] = task
        } else {
            myTasks.insert(task, at: 0)
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private enum HubTaskServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid task request URL."
        case .invalidResponse:
            return "The task server returned an invalid response."
        case .httpStatus(let status):
            return "The task server returned HTTP \(status)."
        }
    }
}
