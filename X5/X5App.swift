import SwiftUI

@main
struct X5App: App {
    @StateObject private var auth = Auth()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
    }
}
