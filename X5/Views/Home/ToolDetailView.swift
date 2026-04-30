import SwiftUI

/// Detail screen shown when tapping any AI tool card on Home.
/// "Coming soon" content with a notify-me hook (no-op stub for now).
struct ToolDetailView: View {
    let tool: HomeTool

    @Environment(\.dismiss) private var dismiss
    @State private var notified = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cover
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tool.title)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(.white)
                        Text(tool.subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))

                        if let tag = tool.tag, let tc = tool.tagColor {
                            Text(tag)
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.7)
                                .foregroundColor(.black)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(tc)
                                .clipShape(Capsule())
                        }
                    }

                    Text("STATUS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 4)

                    HStack(spacing: 12) {
                        Image(systemName: "hammer.fill")
                            .foregroundColor(.accentColor)
                        Text("In development — coming soon")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text("WHAT IT WILL DO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 8)

                    Text(longDescription)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        notified = true
                    } label: {
                        HStack {
                            Image(systemName: notified ? "checkmark.circle.fill" : "bell.fill")
                            Text(notified ? "We will let you know" : "Notify me when ready")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(notified ? Color.green.opacity(0.9) : Color.accentColor)
                        .cornerRadius(14)
                    }
                    .disabled(notified)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cover: some View {
        ZStack {
            LinearGradient(colors: [tool.gradientStart, tool.gradientEnd],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url = tool.videoURL {
                LoopingVideo(url: url)
                    .opacity(0.85)
            } else {
                Image(systemName: tool.icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var longDescription: String {
        switch tool.id {
        case "photo":          return "Generate marketing-grade product and lifestyle photos from a text prompt. Adjust angle, lighting and style without a studio."
        case "video_gen":      return "AI video generation (Kling 3.0). Turn a still or a script into a short clip ready for Reels, TikTok and Shorts."
        case "outfit_swap":    return "Swap outfits on people in any photo while preserving body shape and lighting."
        case "lipsync":        return "Sync lip movement to any audio track. Voice-overs and dubbing for Reels and ads."
        case "design":         return "Brand banners, story tiles, ad sets and pitch decks generated to your brand guide."
        case "voice_tts":      return "Text-to-speech with emotion control. Multiple voices and languages for ads and tutorials."
        case "whatsapp_bot":   return "Auto-responder for incoming WhatsApp leads. Books, qualifies and routes 24/7."
        case "instagram":      return "Content plan generator. Get a 14-day Instagram schedule tuned to your niche and tone."
        case "video_creative": return "Reels and TikTok scripts with hook → tension → CTA structure, ready to film."
        case "lawyer":         return "Generate vetted contracts, NDAs, service acts and proposals tailored to your business."
        case "academy":        return "Open the X5 Academy. Tap the Courses tab in the navigation."
        case "crm":            return "Lightweight CRM for solo founders and small agencies. Pipeline, deals, contacts."
        case "analytics":      return "Daily KPI digest from your channels: ad spend, ROAS, top creatives, conversion."
        case "captions":       return "Caption templates with platform-aware length. This one is live today — tap the card to open."
        case "ai_influencer":  return "Build a consistent virtual influencer character that stays on-model across photos and videos."
        case "edit_image":     return "Edit any photo with AI: face swap, relight, skin enhance, background change."
        case "vfx_library":    return "Cinematic transitions and VFX library. Drop a clip in, pick a style."
        default:               return "More details soon."
        }
    }
}
