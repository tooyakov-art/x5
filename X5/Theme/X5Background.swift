import SwiftUI

/// Steam-style dark navy background with subtle cyan glow at top.
/// Apply with `.x5Background()` to any root view.
struct X5Background: View {
    var body: some View {
        ZStack {
            // Base dark navy
            Color(red: 0.04, green: 0.05, blue: 0.10)

            // Top cyan glow
            RadialGradient(
                colors: [
                    Color(red: 0.15, green: 0.40, blue: 0.65).opacity(0.55),
                    .clear
                ],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 10,
                endRadius: 380
            )

            // Side blue blob
            RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.20, blue: 0.55).opacity(0.40),
                    .clear
                ],
                center: .init(x: -0.05, y: 0.4),
                startRadius: 10,
                endRadius: 360
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
