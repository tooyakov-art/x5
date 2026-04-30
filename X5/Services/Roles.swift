import Foundation

/// Whitelist of emails with developer permissions: can create / edit / delete courses,
/// see the "Create course" button, and bypass purchase gates locally.
/// Source-of-truth admin check is enforced by Supabase RLS — this is just UI gating.
enum Roles {
    static let developerEmails: Set<String> = [
        "tuakov.ursa@gmail.com",
        "tooyakov.art@gmail.com",
        "tooyakov.icloud@gmail.com",
        "tooyakov@icloud.com",
        "tuakov.ursa@icloud.com",
    ]

    static func isDeveloper(_ email: String?) -> Bool {
        guard let e = email?.lowercased() else { return false }
        return developerEmails.contains(e)
    }
}
