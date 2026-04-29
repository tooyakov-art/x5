import SwiftUI

/// Home tab — top segmented control + 3 inner views.
struct ExperimentalHomeView: View {
    @State private var segment: HomeSegment = .photos

    var body: some View {
        VStack(spacing: 0) {
            HomeSegmentedTabs(selected: $segment)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    switch segment {
                    case .photos:    PhotosSection()
                    case .design:    DesignSection()
                    case .contracts: CaptionSection()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 140)  // leave room for bottom dock
            }
        }
    }
}

private struct PhotosSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(eyebrow: "Photo studio", title: "Polish your shots", subtitle: "Pick a treatment, get retouched in seconds.")

            ForEach(["Auto enhance", "Background remove", "Studio portrait", "Product photo"], id: \.self) { name in
                GlassRow(
                    systemImage: "wand.and.stars",
                    title: name,
                    subtitle: "Tap to open",
                    tint: .purple,
                    action: {}
                )
            }
        }
    }
}

private struct DesignSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(eyebrow: "Design lab", title: "Make it pop", subtitle: "Posters, social tiles and ads — in your brand.")

            ForEach(["Brand poster", "Story tile", "Square ad", "Banner 1200×628"], id: \.self) { name in
                GlassRow(
                    systemImage: "paintpalette.fill",
                    title: name,
                    subtitle: "Open template",
                    tint: .pink,
                    action: {}
                )
            }
        }
    }
}

private struct CaptionSection: View {
    @State private var topic: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(eyebrow: "Captions", title: "Words that sell", subtitle: "Type a topic, pick a tone, ship the post.")

            GlassInput(label: "Topic", placeholder: "e.g. opening a coffee shop", text: $topic)

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try a sample tone")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                    Text("Five tailored captions appear instantly. Tap Copy on any to use it.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(Color(red: 0.55, green: 0.6, blue: 0.7))
            Text(title)
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))
        }
        .padding(.bottom, 4)
    }
}
