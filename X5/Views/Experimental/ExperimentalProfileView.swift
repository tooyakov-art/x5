import SwiftUI

struct ExperimentalProfileView: View {
    @EnvironmentObject private var auth: Auth

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOU")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(Color(red: 0.55, green: 0.6, blue: 0.7))
                    Text("Profile")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                }

                if let email = auth.userEmail {
                    GlassCard {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "person.fill").foregroundColor(.white).font(.system(size: 22, weight: .semibold)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Signed in")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))
                                Text(email)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }

                GlassRow(systemImage: "doc.text", title: "Privacy Policy", subtitle: "What we collect & why", tint: Color(red: 0.16, green: 0.41, blue: 0.96), action: {
                    if let url = URL(string: "https://tooyakov-art.github.io/x5site/privacy.html") {
                        UIApplication.shared.open(url)
                    }
                })

                GlassRow(systemImage: "scroll", title: "Terms of Service", subtitle: "How the app may be used", tint: Color(red: 0.13, green: 0.7, blue: 0.45), action: {
                    if let url = URL(string: "https://tooyakov-art.github.io/x5site/terms.html") {
                        UIApplication.shared.open(url)
                    }
                })

                GlassRow(systemImage: "envelope.fill", title: "Contact Support", subtitle: "support@x5studio.app", tint: Color(red: 0.6, green: 0.32, blue: 0.92), action: {
                    if let url = URL(string: "mailto:support@x5studio.app") {
                        UIApplication.shared.open(url)
                    }
                })

                Button {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign out")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
    }
}
