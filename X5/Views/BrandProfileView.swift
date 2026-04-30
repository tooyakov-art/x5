import SwiftUI

struct BrandProfileView: View {
    @EnvironmentObject private var brand: BrandProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Brand name", text: $brand.data.name)
                    TextField("Niche (e.g. third-wave coffee)", text: $brand.data.niche)
                    TextField("Audience (e.g. urban professionals)", text: $brand.data.audience)
                    TextField("Brand words (comma-separated)", text: $brand.data.vocabulary, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Brand voice")
                } footer: {
                    Text("These optional fields personalize generated captions. Stored only on this device.")
                }

                Section {
                    Button("Reset", role: .destructive) {
                        brand.data = .empty
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Brand voice")
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
