import SwiftUI

enum X5Theme {
    static let cyan = Color(red: 0.22, green: 0.78, blue: 1.0)
    static let blue = Color(red: 0.08, green: 0.34, blue: 0.88)
    static let silver = Color(red: 0.78, green: 0.82, blue: 0.88)
    static let black = Color.black
}

struct X5GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(
                LinearGradient(colors: [
                    Color.white.opacity(0.18),
                    X5Theme.blue.opacity(0.16),
                    Color.black.opacity(0.28)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(colors: [
                            Color.white.opacity(0.30),
                            Color.white.opacity(0.045),
                            Color.clear
                        ], center: .topLeading, startRadius: 2, endRadius: 100)
                    )
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [
                            Color.white.opacity(0.30),
                            accent.opacity(0.48),
                            Color.white.opacity(0.08)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: accent.opacity(0.13), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func x5Glass(cornerRadius: CGFloat = 18, accent: Color = X5Theme.cyan) -> some View {
        modifier(X5GlassSurface(cornerRadius: cornerRadius, accent: accent))
    }
}

struct X5LogoText: View {
    var size: CGFloat = 34

    var body: some View {
        Text("X5")
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .tracking(0)
            .shadow(color: X5Theme.cyan.opacity(0.24), radius: 18, x: 0, y: 8)
    }
}
