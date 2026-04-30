import SwiftUI

/// Mandatory after first sign in: pick a role, optionally categories.
/// Writes user_role + specialist_category[] + show_in_hub to profiles.
struct OnboardingView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser

    @State private var role: Role?
    @State private var pickedCategories: Set<String> = []
    @State private var bio: String = ""
    @State private var saving = false
    @State private var errorMessage: String?

    enum Role: String { case specialist, entrepreneur }

    var body: some View {
        ZStack {
            X5Background()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    rolePicker
                    if role == .specialist {
                        categoriesPicker
                        bioField
                    }
                    if role == .entrepreneur {
                        entrepreneurNote
                    }
                    submitButton
                    if let err = errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("X5")
                .font(.system(size: 56, weight: .black))
                .italic()
                .foregroundColor(.white)
                .shadow(color: Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.5), radius: 24)

            Text("Tell us who you are")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)

            Text("This helps us tailor your experience and what you see in Hub.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    private var rolePicker: some View {
        VStack(spacing: 12) {
            roleCard(.specialist,
                     title: "I'm a specialist",
                     subtitle: "I sell my skills (marketer, designer, dev, copywriter, etc.)",
                     systemImage: "person.crop.square.fill")
            roleCard(.entrepreneur,
                     title: "I'm an entrepreneur",
                     subtitle: "I run a business and want to hire specialists",
                     systemImage: "briefcase.fill")
        }
    }

    private func roleCard(_ r: Role, title: String, subtitle: String, systemImage: String) -> some View {
        Button { role = r } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(role == r ? .black : .accentColor)
                    .frame(width: 44, height: 44)
                    .background(role == r ? Color.accentColor : Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: role == r ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(role == r ? .accentColor : .white.opacity(0.3))
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(role == r ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var categoriesPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pick up to 3 categories")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(pickedCategories.count)/3")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HubCategories.all) { cat in
                        let selected = pickedCategories.contains(cat.id)
                        Button {
                            toggle(cat.id)
                        } label: {
                            Text("\(cat.emoji) \(cat.labelEn)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selected ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(selected ? Color.accentColor : Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Short bio (optional)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
            TextField("e.g. 7y in performance marketing for SaaS", text: $bio, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
        }
    }

    private var entrepreneurNote: some View {
        Text("You'll be able to post tasks in Hub and chat with specialists right after.")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.6))
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack {
                if saving { ProgressView().tint(.black) }
                Text(saving ? "Saving…" : "Continue")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSubmit || saving)
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var canSubmit: Bool {
        guard let role else { return false }
        if role == .specialist { return !pickedCategories.isEmpty }
        return true
    }

    private func toggle(_ id: String) {
        if pickedCategories.contains(id) {
            pickedCategories.remove(id)
        } else if pickedCategories.count < 3 {
            pickedCategories.insert(id)
        }
    }

    private func submit() {
        guard let role, let token = auth.accessToken else { return }
        saving = true
        errorMessage = nil
        Task {
            do {
                try await patchProfile(role: role, token: token)
                if let uid = auth.userId {
                    await currentUser.load(userId: uid, accessToken: token)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            saving = false
        }
    }

    private func patchProfile(role: Role, token: String) async throws {
        guard let userId = auth.userId else { return }
        let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
        let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = [
            "user_role": role.rawValue,
            "specialist_category": Array(pickedCategories),
            "show_in_hub": role == .specialist
        ]
        if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["bio"] = bio
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "Onboarding", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Could not save your role."])
        }
    }
}
