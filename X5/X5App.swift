import SwiftUI

@main
struct X5App: App {
    @StateObject private var auth = Auth()
    @StateObject private var history = CaptionHistory()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(history)
                .preferredColorScheme(.dark)
        }
    }
}
