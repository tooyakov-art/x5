import SwiftUI

/// Mandatory after first sign in: collect identity, role, and optional specialist data.
/// Writes name + nickname + user_role + specialist_category[] + show_in_hub to profiles.
struct OnboardingView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService

    @State private var role: Role?
    @State private var name: String = ""
    @State private var nickname: String = ""
    @State private var pickedCategories: Set<String> = []
    @State private var bio: String = ""
    @State private var saving = false
    @State private var errorMessage: String?

    enum Role: String, CaseIterable, Identifiable {
        case specialist
        case entrepreneur

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                identitySection
                roleSection

                if role == .specialist {
                    categoriesSection
                    bioSection
                }

                if role == .entrepreneur {
                    entrepreneurSection
                }

                submitSection
            }
            .scrollContentBackground(.hidden)
            .background { X5Background() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(.accentColor)
        .preferredColorScheme(.dark)
        .onAppear { populateProfileFields() }
        .onChange(of: currentUser.profile) { _ in populateProfileFields() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            X5LogoMark(size: 56)

            Text(loc.t("onb_title"))
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)

            Text(loc.t("onb_subtitle"))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }

    private var identitySection: some View {
        Section {
            TextField(loc.t("edit_name_placeholder"), text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)

            TextField(loc.t("edit_nickname_placeholder"), text: $nickname)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocapitalization(.none)
                .onChange(of: nickname) { value in
                    let cleaned = Self.cleanNickname(value)
                    if cleaned != value {
                        nickname = cleaned
                    }
                }
        } header: {
            Text(loc.t("onb_identity_section"))
        } footer: {
            Text(identityFooter)
        }
    }

    private var roleSection: some View {
        Section {
            Picker(loc.t("onb_role_section"), selection: $role) {
                Text(loc.t("onb_role_specialist")).tag(Role?.some(.specialist))
                Text(loc.t("onb_role_entrepreneur")).tag(Role?.some(.entrepreneur))
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(roleFooter)
        }
    }

    private var categoriesSection: some View {
        Section {
            ForEach(HubCategories.all) { cat in
                let selected = pickedCategories.contains(cat.id)
                Toggle(isOn: categoryBinding(for: cat.id)) {
                    Label(cat.labelEn, systemImage: HubCategories.symbol(for: cat.id))
                }
                .disabled(!selected && pickedCategories.count >= 3)
            }
        } header: {
            Text(loc.t("onb_pick_categories"))
        } footer: {
            Text("\(pickedCategories.count)/3")
        }
    }

    private var bioSection: some View {
        Section {
            TextField(loc.t("onb_bio_placeholder"), text: $bio, axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text(loc.t("onb_bio_label"))
        }
    }

    private var entrepreneurSection: some View {
        Section {
            Text(loc.t("onb_entrepreneur_note"))
                .foregroundColor(.secondary)
        }
    }

    private var submitSection: some View {
        Section {
            Button(action: submit) {
                HStack {
                    if saving {
                        ProgressView()
                    }
                    Text(saving ? loc.t("onb_saving") : loc.t("onb_continue"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit || saving)
        } footer: {
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
            }
        }
    }

    private var identityFooter: String {
        if !nameTrimmed.isEmpty && !hasRealName {
            return loc.t("onb_name_required")
        }
        if !nicknameTrimmed.isEmpty && !isValidNickname {
            return loc.t("onb_nickname_required")
        }
        return loc.t("onb_identity_hint")
    }

    private var roleFooter: String {
        switch role {
        case .specialist:
            return loc.t("onb_role_specialist_sub")
        case .entrepreneur:
            return loc.t("onb_role_entrepreneur_sub")
        case nil:
            return loc.t("onb_role_required")
        }
    }

    private var canSubmit: Bool {
        guard let role else { return false }
        guard hasRealName, isValidNickname else { return false }
        if role == .specialist { return !pickedCategories.isEmpty }
        return true
    }

    private var nameTrimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nicknameTrimmed: String {
        Self.cleanNickname(nickname.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasRealName: Bool {
        let value = nameTrimmed
        let lower = value.lowercased()
        return value.count >= 2 && lower != "user" && lower != "x5"
    }

    private var isValidNickname: Bool {
        nicknameTrimmed.range(of: "^[a-z0-9_]{3,}$", options: .regularExpression) != nil
    }

    private static func cleanNickname(_ value: String) -> String {
        value.lowercased().filter { "abcdefghijklmnopqrstuvwxyz0123456789_".contains($0) }
    }

    private func categoryBinding(for id: String) -> Binding<Bool> {
        Binding {
            pickedCategories.contains(id)
        } set: { isSelected in
            if isSelected {
                if pickedCategories.count < 3 {
                    pickedCategories.insert(id)
                }
            } else {
                pickedCategories.remove(id)
            }
        }
    }

    private func populateProfileFields() {
        guard let p = currentUser.profile else { return }
        let profileName = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileName.isEmpty && profileName.lowercased() != "user" && profileName.lowercased() != "x5" {
            name = profileName
        }
        nickname = Self.cleanNickname((p.nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        if let storedRole = Role(rawValue: p.userRole ?? "") {
            role = storedRole
        }
        pickedCategories = Set(p.specialistCategory ?? [])
        bio = p.bio ?? ""
    }

    private func submit() {
        guard let role else { return }
        saving = true
        errorMessage = nil
        Task {
            do {
                guard let token = await auth.freshAccessToken() else {
                    throw NSError(domain: "Onboarding", code: 401, userInfo: [NSLocalizedDescriptionKey: loc.t("onb_session_expired")])
                }
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
        let baseURL = X5Config.supabaseBaseURL
        let anonKey = X5Config.supabaseAnonKey
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "Onboarding", code: -1, userInfo: [NSLocalizedDescriptionKey: loc.t("onb_save_failed")])
        }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        guard let url = components.url else {
            throw NSError(domain: "Onboarding", code: -1, userInfo: [NSLocalizedDescriptionKey: loc.t("onb_save_failed")])
        }

        let categories = role == .specialist ? Array(pickedCategories) : []
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = [
            "name": nameTrimmed,
            "nickname": nicknameTrimmed,
            "user_role": role.rawValue,
            "specialist_category": categories,
            "show_in_hub": role == .specialist
        ]
        if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["bio"] = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            DiagnosticLogger.log(event: "onboarding_save_failed", extra: [
                "status": "\(http.statusCode)",
                "body": body
            ])
            throw NSError(
                domain: "Onboarding",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "\(loc.t("onb_save_failed")) (\(http.statusCode))"]
            )
        }
    }
}
