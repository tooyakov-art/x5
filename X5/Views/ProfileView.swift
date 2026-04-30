import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var subscription: Subscription
    @EnvironmentObject private var currentUser: CurrentUser
    @Environment(\.dismiss) private var dismiss

    /// When false the toolbar "Done" button is hidden — used when ProfileView is
    /// embedded as a bottom-tab root rather than presented as a sheet.
    var showsDoneButton: Bool = true

    @State private var deleteStage: DeleteStage = .idle
    @State private var errorMessage: String?
    @State private var showingPaywall: Bool = false

    private enum DeleteStage {
        case idle
        case firstConfirm
        case finalConfirm
        case deleting
    }

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection

                if let cats = currentUser.profile?.specialistCategory, !cats.isEmpty {
                    Section("Specialist") {
                        ForEach(cats, id: \.self) { id in
                            HStack {
                                Text(HubCategories.label(for: id))
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor.opacity(0.7))
                            }
                        }
                        if let inHub = currentUser.profile?.showInHub {
                            HStack {
                                Text("Show in Hub")
                                Spacer()
                                Text(inHub ? "On" : "Off")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let links = currentUser.profile?.socialLinks {
                    Section("Social") {
                        if let v = links.telegram, !v.isEmpty {
                            LabeledContent("Telegram", value: v)
                        }
                        if let v = links.whatsapp, !v.isEmpty {
                            LabeledContent("WhatsApp", value: v)
                        }
                        if let v = links.instagram, !v.isEmpty {
                            LabeledContent("Instagram", value: v)
                        }
                    }
                }

                Section("Account") {
                    if let email = currentUser.profile?.email ?? auth.userEmail {
                        LabeledContent("Email", value: email)
                    }
                    if let credits = currentUser.profile?.credits {
                        LabeledContent("Credits", value: "\(credits)")
                    }
                    HStack {
                        Text("Subscription")
                        Spacer()
                        Text(planLabel)
                            .foregroundColor(currentUser.profile?.isPro == true ? .accentColor : .secondary)
                    }
                }

                Section {
                    if subscription.isPro {
                        Button("Manage subscription") {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles").foregroundColor(.accentColor)
                                Text("Upgrade to Pro").foregroundColor(.accentColor)
                            }
                        }
                    }
                }

                Section {
                    Button("Sign out") {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        deleteStage = .firstConfirm
                    } label: {
                        if deleteStage == .deleting {
                            HStack {
                                ProgressView()
                                Text("Deleting…")
                            }
                        } else {
                            Text("Delete Account")
                        }
                    }
                    .disabled(deleteStage == .deleting)
                } header: {
                    Text("Danger zone")
                } footer: {
                    Text(
                        "This will permanently delete your account and all associated data. This action cannot be undone."
                    )
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }

                Section {
                    Link(
                        "Privacy Policy",
                        destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!
                    )
                    Link(
                        "Terms of Service",
                        destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!
                    )
                    Link(
                        "Contact Support",
                        destination: URL(string: "mailto:support@x5studio.app")!
                    )
                }

                Section {
                    HStack {
                        Spacer()
                        Text("X5 · v1.0.0")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .confirmationDialog(
                "Delete account?",
                isPresented: Binding(
                    get: { deleteStage == .firstConfirm },
                    set: { if !$0 { deleteStage = .idle } }
                ),
                titleVisibility: .visible
            ) {
                Button("Continue", role: .destructive) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        deleteStage = .finalConfirm
                    }
                }
                Button("Cancel", role: .cancel) { deleteStage = .idle }
            } message: {
                Text(
                    "This will permanently remove your account and all associated data. You will not be able to recover it."
                )
            }
            .confirmationDialog(
                "Are you absolutely sure?",
                isPresented: Binding(
                    get: { deleteStage == .finalConfirm },
                    set: { if !$0 { deleteStage = .idle } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete forever", role: .destructive) {
                    Task { await runDelete() }
                }
                Button("Cancel", role: .cancel) { deleteStage = .idle }
            } message: {
                Text("Once deleted, your account cannot be recovered.")
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var profileHeaderSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(urlString: currentUser.profile?.avatar,
                           name: currentUser.profile?.name ?? auth.userEmail,
                           size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentUser.profile?.displayName ?? auth.userEmail ?? "User")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(planLabel)
                            .font(.caption)
                            .foregroundColor(currentUser.profile?.isPro == true ? .accentColor : .secondary)
                        if let n = currentUser.profile?.signupNumber {
                            Text("· #\(n)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let nick = currentUser.profile?.nickname, !nick.isEmpty {
                        Text("@\(nick)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            if let bio = currentUser.profile?.bio, !bio.isEmpty {
                Text(bio).font(.callout).foregroundColor(.secondary)
            }
        }
    }

    private var planLabel: String {
        if let p = currentUser.profile?.planLabel { return "\(p)\(currentUser.profile?.isPro == true ? " · active" : "")" }
        return subscription.isPro ? "Pro · active" : "Free"
    }

    private func runDelete() async {
        deleteStage = .deleting
        errorMessage = nil
        do {
            try await auth.deleteAccount()
            await MainActor.run {
                deleteStage = .idle
                dismiss()
            }
        } catch {
            await MainActor.run {
                deleteStage = .idle
                errorMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }
}
