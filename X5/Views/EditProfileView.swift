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
                Section(header: Text(loc.t("edit_specialist")),
                        footer: Text("Включи «Показывать в Hub» — твой профиль появится в Hub, клиенты смогут написать в чат.").font(.caption)) {
                    Toggle(isOn: $showInHub) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t("edit_show_in_hub")).bold()
                            Text("Публичный профиль для клиентов")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
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
                    TextField("Имя", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Никнейм (a-z 0-9 _)", text: $nickname)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                    TextField("Кратко о себе", text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                    Text("\(bio.count) / 500")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section(header: Text(loc.t("edit_social")),
                        footer: Text("Эти ссылки увидят клиенты в твоём профиле в Hub.").font(.caption)) {
                    socialRow(icon: "camera.aperture", color: Color(red: 0.91, green: 0.27, blue: 0.55),
                              name: "Instagram", text: $instagram, placeholder: "@username")
                    socialRow(icon: "paperplane.fill", color: Color(red: 0.16, green: 0.55, blue: 0.93),
                              name: "Telegram", text: $telegram, placeholder: "@username")
                    socialRow(icon: "phone.fill", color: Color(red: 0.15, green: 0.78, blue: 0.40),
                              name: "WhatsApp", text: $whatsapp, placeholder: "+7…")
                    socialRow(icon: "music.note", color: .black.opacity(0.85),
                              name: "TikTok", text: $tiktok, placeholder: "@username")
                    socialRow(icon: "play.rectangle.fill", color: Color(red: 0.92, green: 0.05, blue: 0.10),
                              name: "YouTube", text: $youtube, placeholder: "@channel")
                    socialRow(icon: "briefcase.fill", color: Color(red: 0.04, green: 0.46, blue: 0.71),
                              name: "LinkedIn", text: $linkedin, placeholder: "linkedin.com/in/…")
                    socialRow(icon: "f.cursive", color: Color(red: 0.10, green: 0.33, blue: 0.78),
                              name: "Facebook", text: $facebook, placeholder: "facebook.com/…")
                }

                if let err = errorMessage {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("btn_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
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

    private func socialRow(icon: String, color: Color, name: String,
                           text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 28, height: 28)

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
        if !nickname.isEmpty {
            let pattern = "^[a-z0-9_]{3,}$"
            if nickname.range(of: pattern, options: .regularExpression) == nil { return false }
        }
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
            "name": AnyEncodable(name),
            "nickname": AnyEncodable(nilIfEmpty(nickname)),
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
        dismiss()
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CategoriesPicker: View {
    @Binding var selected: Set<String>

    var body: some View {
        List {
            ForEach(HubCategories.all) { cat in
                Button {
                    toggle(cat.id)
                } label: {
                    HStack {
                        Text("\(cat.emoji)  \(cat.labelEn)")
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
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(id) }
    }
}
