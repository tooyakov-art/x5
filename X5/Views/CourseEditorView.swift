import SwiftUI
import PhotosUI

/// Developer-only course editor. Opened from CoursesView "+" button (create) or by
/// long-pressing a row (edit). Lets developers tweak title/description/price/visibility
/// and upload a cover image. Lessons editor is a separate (later) iteration.
struct CourseEditorView: View {
    @EnvironmentObject private var auth: Auth
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CoursesService()

    /// Pass an existing course to edit it. Pass nil to create a new one.
    let editing: Course?
    var onChange: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var marketingHook: String = ""
    @State private var price: String = "0"
    @State private var isFree: Bool = true
    @State private var isPublic: Bool = false
    @State private var courseLanguage: String = "ru"
    @State private var coverUrl: String?

    @State private var coverItem: PhotosPickerItem?
    @State private var coverPreviewData: Data?
    @State private var uploadingCover = false

    @State private var saving = false
    @State private var deleteConfirm = false
    @State private var errorText: String?

    private var isCreating: Bool { editing == nil }
    private var existingId: String? { editing?.id }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    coverPicker
                }

                Section("Основное") {
                    TextField("Название курса", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Подзаголовок (хук)", text: $marketingHook)
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Цена и доступ") {
                    Toggle("Бесплатный", isOn: $isFree)
                    if !isFree {
                        HStack {
                            Text("Цена, $")
                            Spacer()
                            TextField("0", text: $price)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                    Toggle("Опубликован (видно всем)", isOn: $isPublic)
                }

                Section("Язык") {
                    Picker("Язык курса", selection: $courseLanguage) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                        Text("Қазақша").tag("kk")
                    }
                }

                if !isCreating {
                    Section {
                        Button(role: .destructive) {
                            deleteConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Удалить курс")
                            }
                        }
                    } footer: {
                        Text("Удаление необратимо.")
                    }
                }

                if let err = errorText {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle(isCreating ? "Новый курс" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Сохранить").bold() }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Удалить курс?", isPresented: $deleteConfirm, titleVisibility: .visible) {
                Button("Удалить навсегда", role: .destructive) {
                    Task { await runDelete() }
                }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear { populate() }
            .onChange(of: coverItem) { newValue in
                guard let newValue else { return }
                Task { await loadCoverPreview(newValue) }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var coverPicker: some View {
        PhotosPicker(selection: $coverItem, matching: .images) {
            ZStack {
                if let data = coverPreviewData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if let url = coverUrl, !url.isEmpty, let u = URL(string: url) {
                    CachedAsyncImage(url: u) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
                if uploadingCover {
                    Color.black.opacity(0.4)
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
            Text("Обложка")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    private func populate() {
        guard let c = editing else { return }
        title = c.title
        description = c.description ?? ""
        marketingHook = c.marketingHook ?? ""
        price = String(c.price ?? 0)
        isFree = c.isFree ?? false
        isPublic = c.isPublic ?? false
        courseLanguage = c.courseLanguage ?? "ru"
        coverUrl = c.coverUrl
    }

    private func loadCoverPreview(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data),
           let jpeg = ui.jpegData(compressionQuality: 0.85) {
            coverPreviewData = jpeg
        }
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        saving = true
        defer { saving = false }
        errorText = nil

        var courseId = existingId

        // 1. Create row first if new — gives us a stable id for storage path
        if courseId == nil {
            guard let created = await service.createCourse(title: title, accessToken: token) else {
                errorText = service.error ?? "Не удалось создать курс."
                return
            }
            courseId = created.id
        }
        guard let id = courseId else { return }

        // 2. Upload cover if picked
        if let jpeg = coverPreviewData {
            uploadingCover = true
            _ = await service.uploadCover(courseId: id, jpegData: jpeg, accessToken: token)
            uploadingCover = false
        }

        // 3. Patch other fields
        let priceInt = Int(price) ?? 0
        let fields: [String: Any] = [
            "title": title,
            "description": description.isEmpty ? NSNull() : description,
            "marketing_hook": marketingHook.isEmpty ? NSNull() : marketingHook,
            "price": priceInt,
            "is_free": isFree,
            "is_public": isPublic,
            "course_language": courseLanguage
        ]
        let ok = await service.updateCourse(id: id, fields: fields, accessToken: token)
        if !ok {
            errorText = service.error ?? "Не удалось сохранить."
            return
        }
        onChange()
        dismiss()
    }

    private func runDelete() async {
        guard let id = existingId, let token = auth.accessToken else { return }
        saving = true
        defer { saving = false }
        let ok = await service.deleteCourse(id: id, accessToken: token)
        if ok {
            onChange()
            dismiss()
        } else {
            errorText = service.error ?? "Не удалось удалить."
        }
    }
}
