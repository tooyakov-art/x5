import SwiftUI

/// AI generation hub — placeholder for v1.1.
/// Mirrors the web's Home/Generate landing.
struct GenerateView: View {
    @State private var showCaptionsTool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Hero
                    VStack(spacing: 16) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(.accentColor)
                            .padding(.top, 28)
                        Text("AI Generation")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(.white)
                        Text("Coming soon")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.4)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(Capsule())
                        Text("Image, video and creative generation will land here. We're shipping the first tools step by step.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Roadmap items
                    VStack(spacing: 10) {
                        RoadmapRow(icon: "photo", title: "Image generation", subtitle: "Marketing visuals from a prompt", status: "In development")
                        RoadmapRow(icon: "video", title: "Video generation", subtitle: "Short-form video for socials", status: "Soon")
                        RoadmapRow(icon: "paintbrush", title: "Design lab", subtitle: "Posters, story tiles, ads", status: "Soon")
                        RoadmapRow(icon: "person.crop.circle.badge.plus", title: "AI influencer", subtitle: "Consistent character across shots", status: "Later")
                    }
                    .padding(.top, 8)

                    // Available now: caption templates (existing feature)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AVAILABLE NOW")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.leading, 4)
                            .padding(.top, 8)

                        Button { showCaptionsTool = true } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.14))
                                    Image(systemName: "text.alignleft")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                                .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Caption templates")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Platform-aware caption presets, three tones")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.55))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Generate")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showCaptionsTool) {
                NavigationStack { MainView() }
                    .preferredColorScheme(.dark)
            }
        }
    }
}

private struct RoadmapRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(subtitle).font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Text(status)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
