import SwiftUI
import UIKit

struct GeneratedGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = GeneratedGalleryStore()
    @State private var preview: GeneratedGalleryPreview?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                X5Background()

                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(store.items) { item in
                                Button {
                                    if let image = store.image(for: item) {
                                        preview = GeneratedGalleryPreview(item: item, image: image)
                                    }
                                } label: {
                                    galleryCell(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Общая галерея")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .fullScreenCover(item: $preview) { preview in
                GeneratedGalleryPreviewView(preview: preview) {
                    store.delete(preview.item)
                    self.preview = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.white.opacity(0.45))
            Text("Пока пусто")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("Сгенерированные картинки будут сохраняться здесь.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private func galleryCell(_ item: GeneratedGalleryItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = store.image(for: item) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.07)
                Image(systemName: "photo")
                    .foregroundColor(.white.opacity(0.4))
            }

            LinearGradient(colors: [.clear, .black.opacity(0.68)],
                           startPoint: .center,
                           endPoint: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.category.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.64))
                Text(item.prompt)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct GeneratedGalleryPreview: Identifiable {
    let item: GeneratedGalleryItem
    let image: UIImage
    var id: String { item.id }
}

private struct GeneratedGalleryPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let preview: GeneratedGalleryPreview
    let onDelete: () -> Void

    @State private var showingShare = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    Image(uiImage: preview.image)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 14)
                    Text(preview.item.prompt)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(.bottom, 30)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .navigationTitle("Общая галерея")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { saveToPhotos() } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    Button { showingShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .sheet(isPresented: $showingShare) {
                GeneratedGalleryActivityView(image: preview.image)
            }
        }
    }

    private func saveToPhotos() {
        UIImageWriteToSavedPhotosAlbum(preview.image, nil, nil, nil)
        withAnimation { saveMessage = "Сохранено в Фото" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { saveMessage = nil }
        }
    }
}

private struct GeneratedGalleryActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
