import Foundation
import SwiftUI

/// Storage prefix for home banner & tool-card videos (mirrors web `VID` constant).
let X5_HOME_VIDEO_BASE = "https://afwznqjpshybmqhlewmy.supabase.co/storage/v1/object/public/videos/home"

struct HomeBanner: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let videoFile: String?       // e.g. "zooms.mp4" — under VID base
    let gradientStart: Color
    let gradientEnd: Color
    let toolID: String           // tool to navigate when tapped

    var videoURL: URL? {
        guard let videoFile else { return nil }
        return URL(string: "\(X5_HOME_VIDEO_BASE)/\(videoFile)")
    }
}

struct HomeTool: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String              // SF Symbol fallback
    let videoFile: String?
    let gradientStart: Color
    let gradientEnd: Color
    let tag: String?              // "AI" / "PRO" / "NEW" / "FREE"
    let tagColor: Color?

    var videoURL: URL? {
        guard let videoFile else { return nil }
        return URL(string: "\(X5_HOME_VIDEO_BASE)/\(videoFile)")
    }
}

enum HomeContent {
    static let banners: [HomeBanner] = [
        .init(title: "AI Influencer", subtitle: "Create your virtual influencer",
              videoFile: nil,
              gradientStart: Color(red: 0.1, green: 0.04, blue: 0.16),
              gradientEnd: Color(red: 0.06, green: 0.20, blue: 0.38),
              toolID: "ai_influencer"),
        .init(title: "Create Video", subtitle: "AI video generation — Kling 3.0",
              videoFile: "zooms.mp4",
              gradientStart: Color(red: 0.06, green: 0.05, blue: 0.16),
              gradientEnd: Color(red: 0.09, green: 0.13, blue: 0.24),
              toolID: "video_gen"),
        .init(title: "Face Swap", subtitle: "Swap faces in photos & videos",
              videoFile: "face-swap.mp4",
              gradientStart: Color(red: 0.10, green: 0.10, blue: 0.18),
              gradientEnd: Color(red: 0.06, green: 0.20, blue: 0.38),
              toolID: "edit_image"),
        .init(title: "Transitions", subtitle: "Cinematic scene transitions",
              videoFile: "transitions.mp4",
              gradientStart: Color(red: 0.06, green: 0.05, blue: 0.16),
              gradientEnd: Color(red: 0.14, green: 0.14, blue: 0.24),
              toolID: "vfx_library"),
        .init(title: "Lipsync Studio", subtitle: "Lip sync with audio",
              videoFile: "lipsync2.mp4",
              gradientStart: Color(red: 0.10, green: 0.10, blue: 0.18),
              gradientEnd: Color(red: 0.18, green: 0.10, blue: 0.30),
              toolID: "lipsync")
    ]

    /// 14 tools matching web `toolCards` array.
    static let tools: [HomeTool] = [
        .init(id: "photo", title: "Create Image", subtitle: "AI generation",
              icon: "photo", videoFile: "angles.mp4",
              gradientStart: .indigo, gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.39, green: 0.40, blue: 0.94)),

        .init(id: "video_gen", title: "Create Video", subtitle: "AI video",
              icon: "video", videoFile: "zooms.mp4",
              gradientStart: .orange, gradientEnd: .black,
              tag: "PRO", tagColor: Color(red: 0.96, green: 0.62, blue: 0.04)),

        .init(id: "outfit_swap", title: "Outfit Swap", subtitle: "Swap outfits",
              icon: "tshirt", videoFile: "outfit-swap.mp4",
              gradientStart: .purple, gradientEnd: .black,
              tag: "NEW", tagColor: Color(red: 0.51, green: 0.55, blue: 0.97)),

        .init(id: "lipsync", title: "Lipsync Studio", subtitle: "Lip sync",
              icon: "mouth", videoFile: "lipsync.mp4",
              gradientStart: .cyan, gradientEnd: .black,
              tag: "NEW", tagColor: Color(red: 0.13, green: 0.83, blue: 0.93)),

        .init(id: "design", title: "Design", subtitle: "Banners & creatives",
              icon: "paintbrush", videoFile: nil,
              gradientStart: Color(red: 0.39, green: 0.40, blue: 0.94).opacity(0.4),
              gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.80, green: 1.0, blue: 0.10)),

        .init(id: "voice_tts", title: "Voice TTS", subtitle: "Text to speech",
              icon: "speaker.wave.2.fill", videoFile: "lipsync2.mp4",
              gradientStart: .pink, gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.66, green: 0.55, blue: 0.98)),

        .init(id: "whatsapp_bot", title: "WhatsApp Bot", subtitle: "Auto-responder",
              icon: "bubble.left.and.bubble.right.fill", videoFile: nil,
              gradientStart: Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.4),
              gradientEnd: .black,
              tag: "NEW", tagColor: Color(red: 0.06, green: 0.73, blue: 0.51)),

        .init(id: "instagram", title: "Instagram AI", subtitle: "Content plan",
              icon: "camera.fill", videoFile: nil,
              gradientStart: Color(red: 0.96, green: 0.25, blue: 0.36).opacity(0.4),
              gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.96, green: 0.25, blue: 0.36)),

        .init(id: "video_creative", title: "Video Creative", subtitle: "Reels scripts",
              icon: "film", videoFile: "behind-scenes.mp4",
              gradientStart: .purple, gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.66, green: 0.55, blue: 0.98)),

        .init(id: "lawyer", title: "Lawyer AI", subtitle: "Contracts & docs",
              icon: "doc.text.fill", videoFile: nil,
              gradientStart: Color(red: 0.20, green: 0.83, blue: 0.60).opacity(0.4),
              gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.20, green: 0.83, blue: 0.60)),

        .init(id: "academy", title: "Academy", subtitle: "Courses & training",
              icon: "graduationcap.fill", videoFile: nil,
              gradientStart: Color(red: 0.80, green: 1.0, blue: 0.10).opacity(0.25),
              gradientEnd: .black,
              tag: nil, tagColor: nil),

        .init(id: "crm", title: "CRM", subtitle: "Client management",
              icon: "person.3.fill", videoFile: nil,
              gradientStart: Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.4),
              gradientEnd: .black,
              tag: "NEW", tagColor: Color(red: 0.23, green: 0.51, blue: 0.96)),

        .init(id: "analytics", title: "Analytics", subtitle: "KPI & statistics",
              icon: "chart.bar.fill", videoFile: nil,
              gradientStart: Color(red: 0.80, green: 1.0, blue: 0.10).opacity(0.3),
              gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.80, green: 1.0, blue: 0.10)),

        .init(id: "captions", title: "Captions", subtitle: "Caption templates (live)",
              icon: "text.alignleft", videoFile: nil,
              gradientStart: Color(red: 0.80, green: 1.0, blue: 0.10).opacity(0.4),
              gradientEnd: .black,
              tag: "LIVE", tagColor: Color(red: 0.80, green: 1.0, blue: 0.10))
    ]
}
