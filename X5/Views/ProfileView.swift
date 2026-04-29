import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: Auth
    @Environment(\.dismiss) private var dismiss

    @State private var deleteStage: DeleteStage = .idle
    @State private var errorMessage: String?

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Delete account?",
                isPresented: Binding(
                    get: { deleteStage == .firstConfirm },
                    set: { if !$0 { deleteStage = .idle } }
                )
            ) {
                Button("Cancel", role: .cancel) { deleteStage = .idle }
                Button("Continue", role: .destructive) {
                    deleteStage = .finalConfirm
                }
            } message: {
                Text(
                    "This will permanently remove your account and all associated data. You will not be able to recover it."
                )
            }
            .alert(
                "Are you absolutely sure?",
                isPresented: Binding(
                    get: { deleteStage == .finalConfirm },
                    set: { if !$0 { deleteStage = .idle } }
                )
            ) {
                Button("Cancel", role: .cancel) { deleteStage = .idle }
                Button("Delete forever", role: .destructive) {
                    Task { await runDelete() }
                }
            } message: {
                Text("Once deleted, your account cannot be recovered.")
            }
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
