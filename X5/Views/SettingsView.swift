import SwiftUI

/// Settings sheet — split out of ProfileView. Contains account actions, links, version.
struct SettingsView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var subscription: Subscription
    @Environment(\.dismiss) private var dismiss

    @State private var deleteStage: DeleteStage = .idle
    @State private var errorMessage: String?

    private enum DeleteStage { case idle, firstConfirm, finalConfirm, deleting }

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
                            HStack { ProgressView(); Text("Deleting…") }
                        } else {
                            Text("Delete Account")
                        }
                    }
                    .disabled(deleteStage == .deleting)
                } header: {
                    Text("Danger zone")
                } footer: {
                    Text("This will permanently delete your account and all associated data. This action cannot be undone.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }

                Section {
                    Link("Privacy Policy", destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                    Link("Terms of Service", destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
                    Link("Contact Support", destination: URL(string: "mailto:support@x5studio.app")!)
                }

                Section {
                    HStack {
                        Spacer()
                        Text(versionString).font(.footnote).foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
                Text("This will permanently remove your account and all associated data. You will not be able to recover it.")
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
        }
        .preferredColorScheme(.dark)
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "X5 · v\(v) (\(b))"
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
