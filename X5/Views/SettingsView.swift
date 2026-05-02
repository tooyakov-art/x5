import SwiftUI
import UIKit

/// Settings sheet — split out of ProfileView. Contains account actions, language picker,
/// Face ID toggle, public profile toggle, system links, version.
struct SettingsView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var subscription: Subscription
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss

    @State private var deleteStage: DeleteStage = .idle
    @State private var errorMessage: String?
    @AppStorage("x5.face_id_enabled") private var faceIDEnabled = false
    @AppStorage("x5.promo.enabled") private var promoEnabled = true
    @State private var publicToggle: Bool = true

    private enum DeleteStage { case idle, firstConfirm, finalConfirm, deleting }

    var body: some View {
        NavigationStack {
            List {
                // Account
                Section(loc.t("settings_account")) {
                    if let email = auth.userEmail {
                        LabeledContent(loc.t("settings_email"), value: email)
                    }
                    HStack {
                        Text(loc.t("settings_subscription"))
                        Spacer()
                        Text(subscription.isPro ? loc.t("settings_pro_active") : loc.t("settings_free"))
                            .foregroundColor(subscription.isPro ? .accentColor : .secondary)
                    }
                }

                // Appearance / language — read-only, follows system iOS language
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("settings_language"))
                                    .foregroundColor(.primary)
                                Text("\(loc.current.flag) \(loc.current.label) · из системы")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(loc.t("settings_appearance"))
                } footer: {
                    Text("Язык приложения берётся из языка iPhone. Чтобы сменить — Настройки iOS → X5 → Язык.")
                }

                // Privacy & app
                Section {
                    Toggle(isOn: $faceIDEnabled) {
                        HStack {
                            Image(systemName: "faceid")
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("settings_face_id"))
                                Text(loc.t("settings_face_id_sub"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $publicToggle) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("settings_public_profile"))
                                Text(loc.t("settings_public_profile_sub"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: publicToggle) { newValue in
                        Task { await updatePublic(newValue) }
                    }

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell")
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("settings_notifications"))
                                    .foregroundColor(.primary)
                                Text(loc.t("settings_notifications_sub"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        CacheView()
                    } label: {
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("settings_cache"))
                                    .foregroundColor(.primary)
                                Text(loc.t("settings_cache_sub"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $promoEnabled) {
                        HStack {
                            Image(systemName: "megaphone")
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t("settings_promo"))
                                Text(loc.t("settings_promo_sub"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: promoEnabled) { newValue in
                        if newValue {
                            PushNotifications.shared.schedulePromoLoop()
                        } else {
                            PushNotifications.shared.cancelPromoLoop()
                        }
                    }

                }

                // Sign out
                Section {
                    Button(loc.t("settings_signout")) {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        deleteStage = .firstConfirm
                    } label: {
                        if deleteStage == .deleting {
                            HStack { ProgressView(); Text(loc.t("settings_deleting")) }
                        } else {
                            Text(loc.t("settings_delete"))
                        }
                    }
                    .disabled(deleteStage == .deleting)
                } header: {
                    Text(loc.t("settings_danger"))
                } footer: {
                    Text(loc.t("settings_delete_footer"))
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }

                // Legal
                Section(loc.t("settings_legal")) {
                    Link(loc.t("settings_privacy"), destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                    Link(loc.t("settings_terms"), destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
                    Link(loc.t("settings_support"), destination: URL(string: "mailto:support@x5studio.app")!)
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
            .navigationTitle(loc.t("settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("btn_done")) { dismiss() }
                }
            }
            .confirmationDialog(
                loc.t("settings_delete_confirm"),
                isPresented: Binding(
                    get: { deleteStage == .firstConfirm },
                    set: { if !$0 { deleteStage = .idle } }
                ),
                titleVisibility: .visible
            ) {
                Button(loc.t("btn_continue"), role: .destructive) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        deleteStage = .finalConfirm
                    }
                }
                Button(loc.t("btn_cancel"), role: .cancel) { deleteStage = .idle }
            } message: {
                Text(loc.t("settings_delete_confirm_msg"))
            }
            .confirmationDialog(
                loc.t("settings_delete_sure"),
                isPresented: Binding(
                    get: { deleteStage == .finalConfirm },
                    set: { if !$0 { deleteStage = .idle } }
                ),
                titleVisibility: .visible
            ) {
                Button(loc.t("settings_delete_forever"), role: .destructive) {
                    Task { await runDelete() }
                }
                Button(loc.t("btn_cancel"), role: .cancel) { deleteStage = .idle }
            } message: {
                Text(loc.t("settings_delete_sure_msg"))
            }
            .onAppear {
                publicToggle = currentUser.profile?.isPublic ?? true
            }
        }
        .preferredColorScheme(.dark)
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "X5 · v\(v) (\(b))"
    }

    private func updatePublic(_ value: Bool) async {
        guard let token = auth.accessToken else { return }
        await currentUser.patch("is_public", value: value, accessToken: token)
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
                errorMessage = "\(loc.t("settings_delete_failed")): \(error.localizedDescription)"
            }
        }
    }
}

// Language is system-driven only — see LocalizationService for the auto-detect logic.
