import SwiftUI
import PhotosUI

/// Grid of portfolio items. Used inside ProfileView (own) and UserProfileView (public).
struct PortfolioGrid: View {
    let userId: String
    let canEdit: Bool

    @EnvironmentObject private var auth: Auth
    @StateObject private var service = PortfolioService()
    @State private var showingAdd = false

    private let columns = [GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("РџРѕСЂС‚С„РѕР»РёРѕ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if canEdit {
                    Button {
                        showingAdd = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Р”РѕР±Р°РІРёС‚СЊ")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .x5Glass(cornerRadius: 14)
                    }
                }
            }

            if service.items.isEmpty && !service.isLoading {
                VStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                    Text(canEdit ? "Р—Р°РіСЂСѓР·Рё СЃРІРѕРё СЂР°Р±РѕС‚С‹" : "РџРѕСЂС‚С„РѕР»РёРѕ РїСѓСЃС‚РѕРµ")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .x5Glass(cornerRadius: 18)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(service.items) { item in
                        PortfolioCell(item: item,
                                      canEdit: canEdit,
                                      onDelete: {
                                          guard let token = auth.accessToken else { return }
                                          Task { await service.delete(itemId: item.id, accessToken: token) }
                                      })
                    }
                }
            }
        }
        .task {
            guard let token = auth.accessToken else { return }
            await service.load(userId: userId, accessToken: token)
        }
        .sheet(isPresented: $showingAdd) {
            AddPortfolioItemView { jpeg, title, desc in
                guard let token = auth.accessToken else { return false }
                return await service.addImage(jpegData: jpeg, userId: userId, title: title, description: desc, accessToken: token)
            }
            .preferredColorScheme(.dark)
        }
    }
}
private struct PortfolioCell: View {
    let item: PortfolioItem
    let canEdit: Bool
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Color.white.opacity(0.06)
                if let s = item.mediaUrl, let url = URL(string: s) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.white.opacity(0.5))
                    }
                }
            }
            .frame(height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if canEdit {
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .padding(6)
            }
        }
        .confirmationDialog("РЈРґР°Р»РёС‚СЊ РёР· РїРѕСЂС‚С„РѕР»РёРѕ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("РЈРґР°Р»РёС‚СЊ", role: .destructive) { onDelete() }
            Button("РћС‚РјРµРЅР°", role: .cancel) {}
        }
    }
}
// MARK: - Add item

struct AddPortfolioItemView: View {
    let onSave: (Data, String?, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if let data = imageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Р’С‹Р±СЂР°С‚СЊ С„РѕС‚Рѕ")
                            }
                            .frame(maxWidth: .infinity, minHeight: 100)
                        }
                    }
                    .onChange(of: photoItem) { newValue in
                        Task {
                            if let item = newValue,
                               let data = try? await item.loadTransferable(type: Data.self) {
                                imageData = compress(data)
                            }
                        }
                    }
                }

                Section("РћРїРёСЃР°РЅРёРµ") {
                    TextField("РќР°Р·РІР°РЅРёРµ (РѕРїС†.)", text: $title)
                    TextField("РљРµР№СЃ / РѕРїРёСЃР°РЅРёРµ (РѕРїС†.)", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let err = errorText {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(X5Background())
            .navigationTitle("Р”РѕР±Р°РІРёС‚СЊ РІ РїРѕСЂС‚С„РѕР»РёРѕ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("РћС‚РјРµРЅР°") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("РЎРѕС…СЂР°РЅРёС‚СЊ").bold() }
                    }
                    .disabled(saving || imageData == nil)
                }
            }
        }
    }

    private func save() async {
        guard let data = imageData else { return }
        saving = true
        defer { saving = false }
        let titleTrim = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let descTrim = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await onSave(data, titleTrim.isEmpty ? nil : titleTrim,
                              descTrim.isEmpty ? nil : descTrim)
        if ok {
            dismiss()
        } else {
            errorText = "Не удалось сохранить. Проверь доступ к фото и попробуй другое изображение."
        }
    }

    /// Re-encode picked image as JPEG в‰¤1.5MB to keep uploads fast.
    private func compress(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1600
        let s = image.size
        let scale = min(maxSide / max(s.width, s.height), 1)
        let target = CGSize(width: s.width * scale, height: s.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }
}
