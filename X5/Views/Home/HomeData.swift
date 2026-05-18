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

enum ImageGenerationProvider: String, CaseIterable, Identifiable, Hashable {
    case gptImageMini = "gpt-image-1-mini"
    case gptImage = "gpt-image-1"
    case geminiFlash = "gemini-3.1-flash-image-preview"
    case geminiFlashLite = "gemini-2.5-flash-image-preview"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gptImageMini: return "GPT Image Mini"
        case .gptImage: return "GPT Image"
        case .geminiFlash: return "Gemini Flash Image"
        case .geminiFlashLite: return "Gemini Flash Lite"
        }
    }

    var provider: String {
        switch self {
        case .gptImageMini, .gptImage:
            return "gpt"
        case .geminiFlash, .geminiFlashLite:
            return "google"
        }
    }

    var subtitle: String {
        switch self {
        case .gptImageMini: return "fast OpenAI image model"
        case .gptImage: return "higher quality OpenAI image model"
        case .geminiFlash: return "Google multimodal image model"
        case .geminiFlashLite: return "faster Gemini image preview"
        }
    }
}

struct ImageGenerationCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let examplePrompt: String
    let gradientStart: Color
    let gradientEnd: Color
}

enum ImageGenerationCatalog {
    static let creditCost: Int = 10

    static let custom = ImageGenerationCategory(
        id: "custom",
        title: "Custom",
        subtitle: "Any marketing visual",
        icon: "sparkles",
        examplePrompt: "Premium Instagram ad for a coffee brand, dark studio light, blue glass details",
        gradientStart: X5Style.blue.opacity(0.34),
        gradientEnd: .black
    )

    static let categories: [ImageGenerationCategory] = [
        .init(
            id: "logo",
            title: "Logo",
            subtitle: "Brand mark",
            icon: "seal.fill",
            examplePrompt: "Minimal premium logo for a boutique coffee brand, silver and cyan, black background",
            gradientStart: Color(red: 0.62, green: 0.70, blue: 0.82).opacity(0.42),
            gradientEnd: .black
        ),
        .init(
            id: "story",
            title: "Story",
            subtitle: "Vertical creative",
            icon: "rectangle.portrait.fill",
            examplePrompt: "Instagram story for a luxury skincare launch, product glow, clean text space",
            gradientStart: X5Style.blue.opacity(0.40),
            gradientEnd: .black
        ),
        .init(
            id: "post",
            title: "Post",
            subtitle: "Square feed post",
            icon: "square.grid.2x2.fill",
            examplePrompt: "Square Instagram post for a restaurant opening, cinematic table scene, premium lighting",
            gradientStart: Color(red: 0.39, green: 0.40, blue: 0.94).opacity(0.42),
            gradientEnd: .black
        ),
        .init(
            id: "insta_pack",
            title: "Insta Pack",
            subtitle: "Post + story mood",
            icon: "square.stack.3d.up.fill",
            examplePrompt: "Cohesive Instagram visual package for a fashion brand, post cover, story mood, brand texture",
            gradientStart: X5Style.blueSoft.opacity(0.42),
            gradientEnd: .black
        ),
        .init(
            id: "product",
            title: "Product",
            subtitle: "Ad-ready shot",
            icon: "shippingbox.fill",
            examplePrompt: "Premium product ad for wireless headphones, black acrylic surface, cyan rim light",
            gradientStart: Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.42),
            gradientEnd: .black
        ),
        .init(
            id: "packaging",
            title: "Packaging",
            subtitle: "Box and label",
            icon: "cube.box.fill",
            examplePrompt: "Luxury packaging concept for artisan chocolate, matte black box, silver label, studio render",
            gradientStart: Color(red: 0.52, green: 0.57, blue: 0.68).opacity(0.42),
            gradientEnd: .black
        )
    ]
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

        .init(id: "video_gen", title: "Kling Video", subtitle: "Text/Image to video",
              icon: "video", videoFile: "zooms.mp4",
              gradientStart: X5Style.blue.opacity(0.42), gradientEnd: .black,
              tag: "PRO", tagColor: Color.white.opacity(0.88)),

        .init(id: "outfit_swap", title: "Outfit Swap", subtitle: "Swap outfits",
              icon: "tshirt", videoFile: "outfit-swap.mp4",
              gradientStart: .purple, gradientEnd: .black,
              tag: "NEW", tagColor: Color(red: 0.51, green: 0.55, blue: 0.97)),

        .init(id: "lipsync", title: "Lip Sync", subtitle: "Talking video",
              icon: "mouth", videoFile: "lipsync.mp4",
              gradientStart: X5Style.blue.opacity(0.36), gradientEnd: .black,
              tag: "NEW", tagColor: X5Style.blueSoft),

        .init(id: "design", title: "Design", subtitle: "Banners & creatives",
              icon: "paintbrush", videoFile: nil,
              gradientStart: Color(red: 0.39, green: 0.40, blue: 0.94).opacity(0.4),
              gradientEnd: .black,
              tag: "AI", tagColor: X5Style.blue),

        .init(id: "voice_tts", title: "Voice TTS", subtitle: "Text to speech",
              icon: "speaker.wave.2.fill", videoFile: "lipsync2.mp4",
              gradientStart: .pink, gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.66, green: 0.55, blue: 0.98)),

        .init(id: "whatsapp_bot", title: "WhatsApp Bot", subtitle: "Auto-responder",
              icon: "bubble.left.and.bubble.right.fill", videoFile: nil,
              gradientStart: X5Style.blueSoft.opacity(0.34),
              gradientEnd: .black,
              tag: "NEW", tagColor: X5Style.blueSoft),

        .init(id: "instagram", title: "Instagram AI", subtitle: "Content plan",
              icon: "camera.fill", videoFile: nil,
              gradientStart: X5Style.blue.opacity(0.28),
              gradientEnd: .black,
              tag: "AI", tagColor: X5Style.blue),

        .init(id: "video_creative", title: "Motion Control", subtitle: "Camera moves",
              icon: "film", videoFile: "behind-scenes.mp4",
              gradientStart: .purple, gradientEnd: .black,
              tag: "AI", tagColor: Color(red: 0.66, green: 0.55, blue: 0.98)),

        .init(id: "lawyer", title: "Lawyer AI", subtitle: "Contracts & docs",
              icon: "doc.text.fill", videoFile: nil,
              gradientStart: X5Style.blueSoft.opacity(0.32),
              gradientEnd: .black,
              tag: "AI", tagColor: X5Style.blueSoft),

        .init(id: "academy", title: "Academy", subtitle: "Courses & training",
              icon: "graduationcap.fill", videoFile: nil,
              gradientStart: X5Style.blue.opacity(0.22),
              gradientEnd: .black,
              tag: nil, tagColor: nil),

        .init(id: "crm", title: "CRM", subtitle: "Client management",
              icon: "person.3.fill", videoFile: nil,
              gradientStart: Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.4),
              gradientEnd: .black,
              tag: "NEW", tagColor: Color(red: 0.23, green: 0.51, blue: 0.96)),

        .init(id: "analytics", title: "Analytics", subtitle: "KPI & statistics",
              icon: "chart.bar.fill", videoFile: nil,
              gradientStart: X5Style.blue.opacity(0.26),
              gradientEnd: .black,
              tag: "AI", tagColor: X5Style.blue),

        .init(id: "captions", title: "Captions", subtitle: "Caption templates (live)",
              icon: "text.alignleft", videoFile: nil,
              gradientStart: X5Style.blue.opacity(0.30),
              gradientEnd: .black,
              tag: "LIVE", tagColor: X5Style.blue)
    ]
}
