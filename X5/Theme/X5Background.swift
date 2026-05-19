import SwiftUI

/// Premium black/navy background with a controlled blue glow.
/// Apply with `.x5Background()` to any root view.
struct X5Background: View {
    var showMark: Bool = true

    var body: some View {
        ZStack {
            X5Style.ink

            RadialGradient(
                colors: [
                    X5Style.backgroundBlue.opacity(0.58),
                    .clear
                ],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 10,
                endRadius: 430
            )

            RadialGradient(
                colors: [
                    X5Style.backgroundCyan.opacity(0.30),
                    .clear
                ],
                center: .init(x: -0.06, y: 0.34),
                startRadius: 10,
                endRadius: 360
            )

            if showMark {
                Text("X5")
                    .font(.system(size: 230, weight: .black))
                    .italic()
                    .foregroundColor(.white.opacity(0.035))
                    .kerning(-10)
                    .offset(x: -12, y: -120)
                    .allowsHitTesting(false)
            }

            RadialGradient(
                colors: [
                    X5Style.backgroundCyan.opacity(0.16),
                    .clear
                ],
                center: .init(x: 0.74, y: 0.04),
                startRadius: 4,
                endRadius: 220
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Layers the X5Background underneath the receiver.
    func x5Background() -> some View {
        ZStack {
            X5Background()
            self
        }
    }
}
