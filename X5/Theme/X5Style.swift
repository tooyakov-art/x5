import SwiftUI

enum X5Style {
    static let blue = Color(red: 0.07, green: 0.36, blue: 1.00)
    static let blueSoft = Color(red: 0.16, green: 0.50, blue: 0.95)
    static let ink = Color(red: 0.02, green: 0.025, blue: 0.055)

    static func glassStroke(_ opacity: Double = 0.22) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(opacity),
                Color.white.opacity(0.055),
                blue.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct X5LogoMark: View {
    var size: CGFloat = 56

    var body: some View {
        Text("X5")
            .font(.system(size: size, weight: .black))
            .italic()
            .foregroundColor(.white)
            .kerning(-size * 0.035)
            .shadow(color: X5Style.blueSoft.opacity(0.58), radius: size * 0.38, x: 0, y: 0)
    }
}

private struct X5ClearGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let highlight: Double

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.white.opacity(0.035)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlight),
                            Color.white.opacity(0.028),
                            X5Style.blue.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(X5Style.glassStroke(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 8)
    }
}

private struct X5ClearGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.white.opacity(0.04)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.035),
                            X5Style.blue.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .overlay(Circle().stroke(X5Style.glassStroke(0.22), lineWidth: 1))
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func x5ClearGlass(cornerRadius: CGFloat = 18, highlight: Double = 0.13) -> some View {
        modifier(X5ClearGlassModifier(cornerRadius: cornerRadius, highlight: highlight))
    }

    func x5ClearGlassCircle() -> some View {
        modifier(X5ClearGlassCircleModifier())
    }
}
