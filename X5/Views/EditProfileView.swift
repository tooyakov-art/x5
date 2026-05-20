import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss

    // Mirror of profile fields, mutable
    @State private var name: String = ""
    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var instagram: String = ""
    @State private var telegram: String = ""
    @State private var whatsapp: String = ""
    @State private var tiktok: String = ""
    @State private var youtube: String = ""
    @State private var linkedin: String = ""
    @State private var facebook: String = ""
    @State private var pickedCategories: Set<String> = []
    @State private var showInHub: Bool = false

    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(loc.t("edit_specialist"))) {
                    NavigationLink {
                        CategoriesPicker(selected: $pickedCategories)
                    } label: {
                        HStack {
                            Text(loc.t("edit_categories"))
                            Spacer()
                            Text(pickedCategories.isEmpty ? "—" : "\(pickedCategories.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text(loc.t("edit_about_section"))) {
                    TextField(loc.t("edit_name_placeholder"), text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(loc.t("edit_nickname_placeholder"), text: $nickname)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                        .onChange(of: nickname) { value in
                            nickname = value.lowercased()
                                .filter { "abcdefghijklmnopqrstuvwxyz0123456789_".contains($0) }
                        }
                    TextField(loc.t("edit_bio_placeholder"), text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                    Text("\(bio.count) / 500")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section(header: Text(loc.t("edit_social")),
                        footer: Text(loc.t("edit_social_footer")).font(.caption)) {
                    socialRow(brand: .instagram, name: "Instagram", text: $instagram, placeholder: "@username")
                    socialRow(brand: .telegram, name: "Telegram", text: $telegram, placeholder: "@username")
                    socialRow(brand: .whatsapp, name: "WhatsApp", text: $whatsapp, placeholder: "+7…")
                    socialRow(brand: .tiktok, name: "TikTok", text: $tiktok, placeholder: "@username")
                    socialRow(brand: .youtube, name: "YouTube", text: $youtube, placeholder: "@channel")
                    socialRow(brand: .linkedin, name: "LinkedIn", text: $linkedin, placeholder: "linkedin.com/in/…")
                    socialRow(brand: .facebook, name: "Facebook", text: $facebook, placeholder: "facebook.com/…")
                }

                if let err = errorMessage {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle(loc.t("edit_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("btn_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        X5Feedback.impact()
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text(loc.t("common_save")).bold() }
                    }
                    .disabled(saving || !isValid)
                }
            }
            .onAppear { populate() }
        }
        .preferredColorScheme(.dark)
    }

    private func socialField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .autocapitalization(.none)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
    }

    private func socialRow(brand: SocialBrand, name: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 12) {
            SocialBrandIcon(brand, size: 24)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField(placeholder, text: text)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .font(.system(size: 14))
            }
        }
    }

    private var isValid: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanName.count < 2 || cleanName.lowercased() == "user" || cleanName.lowercased() == "x5" { return false }
        if cleanNickname.range(of: "^[a-z0-9_]{3,}$", options: .regularExpression) == nil { return false }
        return bio.count <= 500
    }

    private func populate() {
        guard let p = currentUser.profile else { return }
        name = p.name ?? ""
        nickname = p.nickname ?? ""
        bio = p.bio ?? ""
        if let s = p.socialLinks {
            instagram = s.instagram ?? ""
            telegram = s.telegram ?? ""
            whatsapp = s.whatsapp ?? ""
            tiktok = s.tiktok ?? ""
            youtube = s.youtube ?? ""
            linkedin = s.linkedin ?? ""
            facebook = s.facebook ?? ""
        }
        pickedCategories = Set(p.specialistCategory ?? [])
        showInHub = p.showInHub ?? false
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        saving = true
        defer { saving = false }

        let socials: [String: String?] = [
            "instagram": nilIfEmpty(instagram),
            "telegram":  nilIfEmpty(telegram),
            "whatsapp":  nilIfEmpty(whatsapp),
            "tiktok":    nilIfEmpty(tiktok),
            "youtube":   nilIfEmpty(youtube),
            "linkedin":  nilIfEmpty(linkedin),
            "facebook":  nilIfEmpty(facebook)
        ]

        var fields: [String: AnyEncodable] = [
            "name": AnyEncodable(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "nickname": AnyEncodable(nickname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
            "bio": AnyEncodable(nilIfEmpty(bio)),
            "social_links": AnyEncodable(socials),
            "specialist_category": AnyEncodable(Array(pickedCategories)),
            "show_in_hub": AnyEncodable(showInHub)
        ]
        // Auto-set role to specialist when toggling Show in Hub on for the first time
        if showInHub && (currentUser.profile?.userRole ?? "").isEmpty {
            fields["user_role"] = AnyEncodable("specialist")
        }
        await currentUser.patchMany(fields, accessToken: token)
        X5Feedback.success()
        dismiss()
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CategoriesPicker: View {
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Set<String>

    var body: some View {
        List {
            ForEach(HubCategories.all) { cat in
                Button {
                    X5Feedback.selection()
                    toggle(cat.id)
                } label: {
                    HStack {
                        Label(cat.labelEn, systemImage: HubCategories.symbol(for: cat.id))
                        Spacer()
                        if selected.contains(cat.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.04, green: 0.05, blue: 0.10))
        .navigationTitle(loc.t("edit_categories"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(loc.t("btn_done")) {
                    X5Feedback.selection()
                    dismiss()
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else if selected.count < 3 { selected.insert(id) }
    }
}
