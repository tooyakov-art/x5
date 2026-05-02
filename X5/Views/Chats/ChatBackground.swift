import SwiftUI

/// Telegram-inspired chat backdrop: subtle SF Symbols scattered in a
/// repeating diagonal grid over the dark app surface. Pure SwiftUI Canvas —
/// no asset bundle, no PNG, scales to any device size, dark-mode native.
///
/// Visible characters are drawn at ~6% opacity so they read as texture, not
/// content, and never compete with messages.
struct ChatBackground: View {
    /// Base solid color matches `Color(red: 0.04, green: 0.05, blue: 0.10)`
    /// used elsewhere in the app for the dark surface.
    private let surface = Color(red: 0.04, green: 0.05, blue: 0.10)

    /// Symbols rotated through the grid. Light, friendly, not branded —
    /// chat / creative / messaging / love / work motifs that match X5.
    private let glyphs: [String] = [
        "✦", "✧", "✩", "✪", "❀", "❁", "❃", "❋",
        "♡", "✿", "❄︎", "✺", "❂", "✻", "❉"
    ]

    /// Cell size in points. Smaller = denser pattern.
    private let cellSize: CGFloat = 48

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cellSize)) + 1
            let rows = Int(ceil(size.height / cellSize)) + 2

            for row in 0..<rows {
                for col in 0..<cols {
                    // Stagger every other row by half a cell — diagonal feel.
                    let xOffset: CGFloat = (row % 2 == 0) ? 0 : cellSize / 2
                    let x = CGFloat(col) * cellSize + xOffset
                    let y = CGFloat(row) * cellSize

                    // Deterministic glyph + rotation per (row,col) — pattern
                    // looks generative but is stable across redraws.
                    let glyphIndex = (row * 7 + col * 3) % glyphs.count
                    let rotation = Double((row * 17 + col * 11) % 360)

                    let text = Text(glyphs[glyphIndex])
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.white.opacity(0.07))

                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .degrees(rotation))
                        layer.draw(text, at: .zero, anchor: .center)
                    }
                }
            }
        }
        .background(surface)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
