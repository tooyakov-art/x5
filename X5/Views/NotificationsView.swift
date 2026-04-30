import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "bell")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No notifications yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("When someone replies to your task, accepts your offer or sends a chat message, it will appear here.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
