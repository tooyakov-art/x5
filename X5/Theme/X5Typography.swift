import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum X5Typography {
    static func installAppearance() {
        #if canImport(UIKit)
        let titleFont = roundedUIFont(size: 17, weight: .semibold)
        let largeTitleFont = roundedUIFont(size: 34, weight: .bold)
        let captionFont = roundedUIFont(size: 12, weight: .semibold)

        UINavigationBar.appearance().titleTextAttributes = [
            .font: titleFont,
            .foregroundColor: UIColor.white
        ]
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: largeTitleFont,
            .foregroundColor: UIColor.white
        ]

        UITabBarItem.appearance().setTitleTextAttributes([.font: captionFont], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: captionFont], for: .selected)

        UISegmentedControl.appearance().setTitleTextAttributes([.font: roundedUIFont(size: 13, weight: .semibold)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: roundedUIFont(size: 13, weight: .bold)], for: .selected)
        #endif
    }

    #if canImport(UIKit)
    private static func roundedUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }
    #endif
}

private struct X5TypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.body, design: .rounded))
            .fontDesign(.rounded)
    }
}

extension View {
    func x5Typography() -> some View {
        modifier(X5TypographyModifier())
    }
}
