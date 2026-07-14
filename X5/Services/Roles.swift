import Foundation

/// UI mirror of the server-side developer gate.
///
/// Access is tied only to immutable Supabase user IDs. Email addresses and
/// editable profile fields must never grant course-management permissions.
/// Supabase RLS remains the source of truth for every write operation.
enum Roles {
    static let developerUserIds: Set<String> = [
        "f3eea23f-0aeb-405b-ab35-2c53173b7a8f",
        "eee55a08-18d1-46e3-a303-1411d1bb9333",
    ]

    static func isDeveloper(_ email: String?) -> Bool {
        isDeveloper(email: email, userId: nil)
    }

    static func isDeveloper(email _: String?, userId: String?) -> Bool {
        guard let userId else { return false }
        return developerUserIds.contains(userId.lowercased())
    }
}
