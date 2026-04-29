import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: Auth

    var body: some View {
        Group {
            if auth.isAuthenticated {
                AppTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isAuthenticated)
    }
}
