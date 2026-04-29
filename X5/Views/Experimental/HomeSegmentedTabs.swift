import SwiftUI

enum HomeSegment: String, CaseIterable {
    case photos, design, contracts

    var label: String {
        switch self {
        case .photos: return "Photo"
        case .design: return "Design"
        case .contracts: return "Caption"
        }
    }

    var icon: String {
        switch self {
        case .photos: return "photo.on.rectangle.angled"
        case .design: return "paintbrush.pointed.fill"
        case .contracts: return "text.alignleft"
        }
    }

    var tint: Color {
        switch self {
        case .photos: return Color(red: 0.6, green: 0.32, blue: 0.92)   // purple
        case .design: return Color(red: 0.93, green: 0.34, blue: 0.62)  // pink
        case .contracts: return Color(red: 0.16, green: 0.41, blue: 0.96) // blue
        }
    }
}

/// Segmented control with sliding pill — matches web's top segmented control.
struct HomeSegmentedTabs: View {
    @Binding var selected: HomeSegment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selected = segment
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: segment.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selected == segment ? segment.tint : Color(red: 0.55, green: 0.6, blue: 0.7).opacity(0.6))
                        Text(segment.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selected == segment ? Color(red: 0.06, green: 0.09, blue: 0.16) : Color(red: 0.45, green: 0.5, blue: 0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            if selected == segment {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }
}
