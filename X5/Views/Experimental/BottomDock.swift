import SwiftUI

enum BottomTab: String, CaseIterable {
    case home, courses, profile

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .courses: return "graduationcap.fill"
        case .profile: return "person.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: return Color(red: 0.16, green: 0.41, blue: 0.96)
        case .courses: return Color(red: 0.6, green: 0.32, blue: 0.92)
        case .profile: return Color(red: 0.13, green: 0.7, blue: 0.45)
        }
    }
}

/// Floating bottom dock — frosted pill with 3 main app sections.
struct BottomDock: View {
    @Binding var selected: BottomTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BottomTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selected = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(selected == tab ? tab.tint : Color(red: 0.55, green: 0.6, blue: 0.7).opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            ZStack {
                                if selected == tab {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                        .scaleEffect(1.05)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 24, x: 0, y: 12)
    }
}
