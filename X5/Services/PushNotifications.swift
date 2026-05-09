import Foundation
import UIKit
import UserNotifications

/// Manages APNs registration and persists the device token to profiles.push_token.
@MainActor
final class PushNotifications: NSObject, ObservableObject {
    static let shared = PushNotifications()

    override init() {
        super.init()
        // Seed promo toggle to ON for first launch — @AppStorage default in
        // SettingsView only affects UI binding, the underlying UserDefaults
        // key stays nil until the user toggles. Without this seed,
        // schedulePromoLoop() would silently bail on first launch.
        if UserDefaults.standard.object(forKey: Self.promoEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.promoEnabledKey)
        }
    }

    @Published private(set) var permissionGranted: Bool = false
    @Published private(set) var deviceToken: String?

    /// Last user we synced the token for. Re-sync when this changes.
    private var lastSyncedUserId: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    /// Call after sign-in. Asks permission and registers with APNs.
    func bootstrap() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                self.permissionGranted = granted
                if granted {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            } catch {
                self.permissionGranted = false
            }
        }
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        Task { await syncToken() }
    }

    func didFailToRegister(error: Error) {
        // No-op: surface to UI later if needed
    }

    // MARK: - Promo notifications
    //
    // Local marketing nudges every 5 minutes — never travel through APNs.
    // iOS allows at most 64 pending local notifications, so we schedule a
    // rolling batch covering the next ~hour and refresh on each foreground.

    /// Identifier prefix so we can wipe just our promo notifications without
    /// touching anything else.
    private static let promoIDPrefix = "x5.promo."

    /// Toggle key in UserDefaults — UI flips it via @AppStorage.
    static let promoEnabledKey = "x5.promo.enabled"

    /// Localized headlines + bodies. Cycle through on each scheduled slot.
    /// Tone: friendly, action-oriented, never aggressive.
    private static let promoMessages: [(title: String, body: String)] = [
        ("X5 ✨", "Закинь новый кадр в портфолио — пусть видят твой стиль."),
        ("Hub 🔥", "В Hub появились задания. Лови, пока не разобрали."),
        ("Курсы 🎓", "Новые уроки вышли — прокачай навыки."),
        ("Сторис ✦", "Добавь сторис чтоб подписчики не забыли тебя."),
        ("Чаты 💬", "Кто-то ищет тебя для проекта. Глянь сообщения."),
        ("Профиль 🌟", "Подкрути аватар — на яркие профили кликают чаще."),
        ("Pro 🚀", "Pro даёт безлимит на всё. Посмотри что внутри."),
        ("X5 ✨", "Покажи новую работу — лента ждёт.")
    ]

    /// Schedule a rolling batch of 12 future promos, one every 5 minutes.
    /// Idempotent: cancels any pending promos first.
    func schedulePromoLoop() {
        guard UserDefaults.standard.bool(forKey: Self.promoEnabledKey) else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                  || settings.authorizationStatus == .provisional else { return }

            cancelPromoLoop()

            // 12 slots × 5 min = 60 min ahead. App refreshes the queue on
            // each foreground so the user always has an hour scheduled.
            let interval: TimeInterval = 5 * 60
            for slot in 1...12 {
                let copy = Self.promoMessages[(slot - 1) % Self.promoMessages.count]
                let content = UNMutableNotificationContent()
                content.title = copy.title
                content.body = copy.body
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: interval * TimeInterval(slot),
                    repeats: false
                )
                let id = "\(Self.promoIDPrefix)\(slot)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    /// Removes all pending promo notifications. Call on sign-out or when the
    /// user disables the toggle. Uses the iOS 16 async API so the closure
    /// stays inside the @MainActor isolation contract instead of jumping to
    /// an arbitrary completion-handler queue.
    func cancelPromoLoop() {
        Task {
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.promoIDPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func currentUserDidChange(userId: String?, accessToken: String?) {
        guard let _ = userId, let _ = accessToken else {
            lastSyncedUserId = nil
            return
        }
        Task { await syncToken() }
    }

    /// Pushes the current deviceToken into profiles.push_token for the current user.
    private func syncToken() async {
        guard let token = deviceToken else { return }
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token"),
            !userId.isEmpty,
            lastSyncedUserId != userId
        else { return }

        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["push_token": token])
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            lastSyncedUserId = userId
        }
    }
}

// MARK: - AppDelegate adapter (handles APNs callbacks)

final class X5AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotifications.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotifications.shared.didFailToRegister(error: error)
        }
    }

    /// Show banner + sound when a notification arrives while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge, .list])
    }
}
