import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
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
                Section(header: Text("About")) {
                    TextField("Display name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Nickname (a-z 0-9 _)", text: $nickname)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                    TextField("Short bio", text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                    Text("\(bio.count) / 500")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Specialist")) {
                    Toggle("Show in Hub", isOn: $showInHub)
                    NavigationLink {
                        CategoriesPicker(selected: $pickedCategories)
                    } label: {
                        HStack {
                            Text("Categories")
                            Spacer()
                            Text(pickedCategories.isEmpty ? "None" : "\(pickedCategories.count) selected")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Social links")) {
                    socialField("Instagram", text: $instagram, placeholder: "@username")
                    socialField("Telegram", text: $telegram, placeholder: "@username")
                    socialField("WhatsApp", text: $whatsapp, placeholder: "+7…")
                    socialField("TikTok", text: $tiktok, placeholder: "https://tiktok.com/@…")
                    socialField("YouTube", text: $youtube, placeholder: "https://youtube.com/@…")
                    socialField("LinkedIn", text: $linkedin, placeholder: "https://linkedin.com/in/…")
                    socialField("Facebook", text: $facebook, placeholder: "https://facebook.com/…")
                }

                if let err = errorMessage {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Save").bold() }
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
