import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var sub: Subscription
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)

                Text("X5 Pro")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Unlock everything for marketers and creators.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 14) {
                    Feature(text: "Unlimited captions across all platforms")
                    Feature(text: "Marketing chat (coming soon)")
                    Feature(text: "Full courses library")
                    Feature(text: "Hire vetted marketers")
                    Feature(text: "Brand voice profile saved across devices")
                    Feature(text: "Priority support")
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 10) {
                    VStack(spacing: 4) {
                        Text("Subscribe — \(Subscription.monthlyPrice) / month")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.black.opacity(0.5))
                        Text("Coming soon")
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor.opacity(0.5))
                    .cornerRadius(16)

                    Text("In-app purchase will be available soon. We're finalizing the App Store subscription.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                }

                HStack(spacing: 18) {
                    Link("Terms", destination: URL(string: "https://tooyakov-art.github.io/x5site/terms.html")!)
                    Link("Privacy", destination: URL(string: "https://tooyakov-art.github.io/x5site/privacy.html")!)
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
        }
    }
}

private struct Feature: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}
