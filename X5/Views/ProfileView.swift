import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var subscription: Subscription
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
                Section("Account") {
                    if let email = auth.userEmail {
                        LabeledContent("Email", value: email)
                    }
                    HStack {
                        Text("Subscription")
                        Spacer()
                        Text(subscription.isPro ? "Pro · active" : "Free")
                            .foregroundColor(subscription.isPro ? .accentColor : .secondary)
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
