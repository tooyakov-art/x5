import Foundation

actor AppAnalyticsService {
    static let shared = AppAnalyticsService()

    enum Event: String {
        case firstOpen = "first_open"
        case registrationStarted = "registration_started"
        case registrationCompleted = "registration_completed"
        case appOpen = "app_open"
        case login
        case paywallOpened = "paywall_opened"
        case purchaseStarted = "purchase_started"
        case purchaseSucceeded = "purchase_succeeded"
        case purchaseFailed = "purchase_failed"
        case purchaseCancelled = "purchase_cancelled"
        case purchaseRestored = "purchase_restored"
    }

    private let installationKey = "x5.analytics.installation_id"
    private let firstOpenKey = "x5.analytics.first_open_sent"
    private var lastLaunchAt: Date?
    private var installationId: UUID {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: installationKey), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: installationKey)
        return id
    }

    func recordLaunch(accessToken: String?) async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: firstOpenKey) {
            if await record(.firstOpen, accessToken: accessToken) {
                defaults.set(true, forKey: firstOpenKey)
            }
        }
        if let lastLaunchAt, Date().timeIntervalSince(lastLaunchAt) < 30 { return }
        lastLaunchAt = Date()
        _ = await record(.appOpen, accessToken: accessToken)
        if accessToken != nil {
            _ = await record(.login, accessToken: accessToken)
        }
    }

    @discardableResult
    func record(_ event: Event, accessToken: String?, metadata: [String: String] = [:]) async -> Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        let locale = Locale.current.identifier
        let country = Locale.current.region?.identifier
        let now = ISO8601DateFormatter().string(from: Date())

        var body: [String: Any] = [
            "p_event_id": UUID().uuidString,
            "p_installation_id": installationId.uuidString,
            "p_event_name": event.rawValue,
            "p_platform": "ios",
            "p_source": "app_store",
            "p_locale": locale,
            "p_occurred_at": now,
            "p_metadata": metadata
        ]
        if let version { body["p_app_version"] = version }
        if let build { body["p_build_number"] = build }
        if let country { body["p_country_code"] = country }
        guard JSONSerialization.isValidJSONObject(body),
              let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return false }

        let url = X5Config.supabaseBaseURL.appendingPathComponent("rest/v1/rpc/record_app_event")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(X5Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? X5Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 8

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
