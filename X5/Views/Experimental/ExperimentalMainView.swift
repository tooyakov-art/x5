import SwiftUI

/// Experimental Liquid-Glass main shell — copies the layout of the x5 web version:
/// liquid background + glass-panel container + bottom dock + segmented home.
/// Used only when `X5_EXPERIMENTAL_UI` flag is on (see `ContentView`).
struct ExperimentalMainView: View {
    @EnvironmentObject private var auth: Auth
    @State private var bottomTab: BottomTab = .home

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                Group {
                    switch bottomTab {
                    case .home:    ExperimentalHomeView()
                    case .courses: ExperimentalCoursesView()
                    case .profile: ExperimentalProfileView()
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 16)

            VStack {
                Spacer()
                BottomDock(selected: $bottomTab)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 640)
            }
        }
        .preferredColorScheme(.light)
    }
}
