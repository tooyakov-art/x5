import SwiftUI

struct NotificationsView: View {
    private let loc = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "bell")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                    Text(loc.t("notif_empty"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(loc.t("notif_empty_desc"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle(loc.t("notif_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("btn_done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
