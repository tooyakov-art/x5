import SwiftUI

/// Animated liquid-glass background with drifting gradient blobs.
/// Mimics the `liquid-bg` blobs from the x5 web version.
struct LiquidBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Base
            Color(red: 0.94, green: 0.95, blue: 0.96)
                .ignoresSafeArea()

            // Blob 1 — purple, top-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.69, green: 0.45, blue: 0.95), .clear],
                        center: .center, startRadius: 5, endRadius: 280
                    )
                )
                .frame(width: 560, height: 560)
                .offset(x: animate ? -120 : -180, y: animate ? -260 : -200)
                .blur(radius: 60)

            // Blob 2 — blue, right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.36, green: 0.52, blue: 1.0), .clear],
                        center: .center, startRadius: 5, endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: animate ? 180 : 140, y: animate ? 80 : 140)
                .blur(radius: 70)

            // Blob 3 — pink, bottom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.43, blue: 0.65), .clear],
                        center: .center, startRadius: 5, endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .offset(x: animate ? -60 : 60, y: animate ? 320 : 360)
                .blur(radius: 65)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}
