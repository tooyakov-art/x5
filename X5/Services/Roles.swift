import Foundation

/// Whitelist of emails with developer permissions: can create / edit / delete courses,
/// see the "Create course" button, and bypass purchase gates locally.
/// Source-of-truth admin check is enforced by Supabase RLS — this is just UI gating.
enum Roles {
    static let developerEmails: Set<String> = [
        "adilkhanskii@gmail.com",
        "tuakov.ursa@gmail.com",
        "tooyakov.art@gmail.com",
        "tooyakov.icloud@gmail.com",
        "tooyakov@icloud.com",
        "tuakov.ursa@icloud.com",
    ]

    static let developerUserIds: Set<String> = [
        "eee55a08-18d1-46e3-a303-1411d1bb9333",
        "9ae99a45-91ac-486a-b7ec-e6614b7bc257",
        "496071cf-7c5b-43e8-886e-9f43c4618f90",
    ]

    static func isDeveloper(_ email: String?) -> Bool {
        isDeveloper(email: email, userId: nil)
    }

    static func isDeveloper(email: String?, userId: String?) -> Bool {
        if let userId, developerUserIds.contains(userId.lowercased()) {
            return true
        }
        guard let e = email?.lowercased() else { return false }
        return developerEmails.contains(e)
    }
}
