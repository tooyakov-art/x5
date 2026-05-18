import SwiftUI
import UIKit
import PencilKit

struct ImageGeneratorView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService

    let category: ImageGenerationCategory

    @State private var prompt: String
    @State private var selectedProvider: ImageGenerationProvider
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedAsset: GeneratedImageAsset?
    @State private var viewerAsset: GeneratedImageAsset?
    @State private var showingGallery = false
    @StateObject private var gallery = GeneratedGalleryStore()
    @FocusState private var promptFocused: Bool

    init(category: ImageGenerationCategory = ImageGenerationCatalog.custom, provider: ImageGenerationProvider = .gpt) {
        self.category = category
        _prompt = State(initialValue: category.examplePrompt)
        _selectedProvider = State(initialValue: provider)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                providerPanel
                promptPanel
                generateButton

                if isGenerating {
                    GenerationAnimationView(provider: selectedProvider, category: category)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                resultPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(generatorBackdrop)
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingGallery = true } label: {
                    Image(systemName: "photo.stack")
                }
                .accessibilityLabel(loc.t("gen_gallery"))
            }
        }
        .task { await refreshProfileIfPossible() }
        .sheet(isPresented: $showingGallery) {
            GeneratedGalleryView()
        }
        .fullScreenCover(item: $viewerAsset) { asset in
            GeneratedImageViewer(asset: asset, onImageUpdated: { image in
                if var updated = generatedAsset {
                    updated.image = image
                    generatedAsset = updated
                }
            }, onSaveToGallery: { image in
                saveAssetToGallery(asset, image: image)
            })
            .environmentObject(loc)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(colors: [category.gradientStart, X5Style.blue.opacity(0.28)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Text("\(ImageGenerationCatalog.creditCost) \(loc.t("gen_credits"))")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.88))
                    .clipShape(Capsule())
            }

            Text(categoryTitle)
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(categorySubtitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))
        }
        .padding(18)
        .x5ClearGlass(cornerRadius: 20, highlight: 0.13)
    }

    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(loc.t("gen_provider"))

            Picker(loc.t("gen_provider"), selection: $selectedProvider) {
                ForEach(ImageGenerationProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)

            HStack {
                Label("\(ImageGenerationCatalog.creditCost)", systemImage: "creditcard")
                Spacer()
                Text(balanceText)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.58))
        }
        .padding(14)
        .x5ClearGlass(cornerRadius: 18, highlight: 0.10)
    }

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(loc.t("gen_prompt"))

            TextField(category.examplePrompt, text: $prompt, axis: .vertical)
                .focused($promptFocused)
                .lineLimit(4...7)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(14)
                .background(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                quickPrompt(categoryTitle)
                quickPrompt(loc.t("gen_product_ad"))
                quickPrompt(loc.t("gen_clean_layout"))
            }
        }
        .padding(14)
        .x5ClearGlass(cornerRadius: 18, highlight: 0.11)
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(generateButtonTitle)
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canGenerate ? Color.white.opacity(0.92) : Color.gray.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate || isGenerating)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let generatedAsset {
            Button {
                viewerAsset = generatedAsset
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Image(uiImage: generatedAsset.image)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    HStack {
                        Label(loc.t("gen_open_viewer"), systemImage: "arrow.up.left.and.arrow.down.right")
                        Spacer()
                        Text("\(generatedAsset.costCredits) \(loc.t("gen_credits"))")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.82))
                }
                .padding(12)
                .x5ClearGlass(cornerRadius: 18, highlight: 0.10)
            }
            .buttonStyle(.plain)
        } else if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red.opacity(0.95))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var generatorBackdrop: some View {
        ZStack {
            X5Background()
            RadialGradient(colors: [category.gradientStart.opacity(0.45), Color.clear],
                           center: .topTrailing, startRadius: 10, endRadius: 280)
                .ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.13, green: 0.33, blue: 0.55).opacity(0.24), Color.clear],
                           center: .bottomLeading, startRadius: 20, endRadius: 320)
                .ignoresSafeArea()
        }
    }

    private var currentCredits: Int? {
        guard let profile = currentUser.profile else { return nil }
        return profile.credits ?? 0
    }

    private var hasEnoughCredits: Bool {
        guard let currentCredits else { return false }
        return currentCredits >= ImageGenerationCatalog.creditCost
    }

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        currentCredits != nil &&
        hasEnoughCredits
    }

    private var balanceText: String {
        guard let currentCredits else { return loc.t("gen_loading_balance") }
        return "\(loc.t("gen_balance")): \(currentCredits)"
    }

    private var generateButtonTitle: String {
        if isGenerating { return loc.t("gen_generating") }
        if currentCredits == nil { return loc.t("gen_loading_balance") }
        if !hasEnoughCredits { return "\(loc.t("gen_need")) \(ImageGenerationCatalog.creditCost) \(loc.t("gen_credits"))" }
        return loc.t("gen_generate")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.45))
    }

    private func quickPrompt(_ text: String) -> some View {
        Button {
            prompt = text == categoryTitle ? category.examplePrompt : "\(text) for \(category.title.lowercased()), premium X5 style"
            promptFocused = true
        } label: {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .x5ClearGlass(cornerRadius: 14, highlight: 0.10)
        }
        .buttonStyle(.plain)
    }

    private func refreshProfileIfPossible() async {
        guard let uid = auth.userId, let token = await auth.freshAccessToken() else { return }
        await currentUser.load(userId: uid, accessToken: token)
    }

    private func generate() async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        guard !isGenerating else { return }

        promptFocused = false
        isGenerating = true
        errorMessage = nil
        generatedAsset = nil
        defer { isGenerating = false }

        await refreshProfileIfPossible()

        guard currentCredits != nil else {
            errorMessage = loc.t("gen_loading_balance")
            return
        }
        guard hasEnoughCredits else {
            errorMessage = loc.t("gen_not_enough_credits")
            return
        }

        do {
            let response = try await auth.supabase.generateImage(
                prompt: cleanPrompt,
                provider: selectedProvider,
                category: category
            )
            guard let data = Data(base64Encoded: response.imageBase64),
                  let image = UIImage(data: data)
            else {
                throw ImageGeneratorError.invalidImage
            }

            let asset = GeneratedImageAsset(
                image: image,
                prompt: response.prompt,
                provider: response.provider ?? selectedProvider.rawValue,
                category: response.category ?? category.id,
                costCredits: response.costCredits ?? ImageGenerationCatalog.creditCost,
                creditsRemaining: response.creditsRemaining
            )
            generatedAsset = asset
            _ = saveAssetToGallery(asset, image: image)
            viewerAsset = asset
            await refreshProfileIfPossible()
            DiagnosticLogger.log(event: "image_generated", extra: [
                "provider": selectedProvider.rawValue,
                "category": category.id
            ])
        } catch {
            DiagnosticLogger.log(event: "image_generation_failed", extra: [
                "summary": error.localizedDescription,
                "provider": selectedProvider.rawValue,
                "category": category.id
            ])
            errorMessage = error.localizedDescription
        }
    }

    private var categoryTitle: String {
        localized("gen_category_\(category.id)_title", fallback: category.title)
    }

    private var categorySubtitle: String {
        localized("gen_category_\(category.id)_subtitle", fallback: category.subtitle)
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = loc.t(key)
        return value == key ? fallback : value
    }

    @discardableResult
    private func saveAssetToGallery(_ asset: GeneratedImageAsset, image: UIImage) -> Bool {
        gallery.save(
            image: image,
            prompt: asset.prompt,
            provider: asset.provider,
            category: asset.category,
            costCredits: asset.costCredits
        ) != nil
    }
}

private struct GeneratedImageAsset: Identifiable {
    let id = UUID()
    var image: UIImage
    let prompt: String
    let provider: String
    let category: String
    let costCredits: Int
    let creditsRemaining: Int?
}

private struct GenerationAnimationView: View {
    @EnvironmentObject private var loc: LocalizationService

    let provider: ImageGenerationProvider
    let category: ImageGenerationCategory

    @State private var rotating = false
    @State private var pulsing = false
    @State private var scanning = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 8)
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        LinearGradient(colors: [Color.white, X5Style.blue],
                                       startPoint: .leading,
                                       endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                Image(systemName: category.icon)
                    .font(.system(size: pulsing ? 24 : 20, weight: .bold))
                    .foregroundColor(.white)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(provider.title) \(loc.t("gen_is_generating"))")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                Text("\(loc.t("gen_building")) \(localizedCategoryTitle.lowercased())")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))
                generationPulseBars
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(16)
        .x5ClearGlass(cornerRadius: 18, highlight: 0.12)
        .onAppear {
            rotating = true
            pulsing = true
            scanning = true
        }
        .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: rotating)
    }

    private var generationPulseBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(colors: [Color.white.opacity(0.92), X5Style.blue.opacity(0.85)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
                    .frame(width: 8, height: scanning ? CGFloat(8 + (index % 4) * 5) : 6)
                    .opacity(scanning ? 0.95 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.07),
                        value: scanning
                    )
            }
        }
        .frame(height: 28, alignment: .bottom)
    }

    private var localizedCategoryTitle: String {
        let key = "gen_category_\(category.id)_title"
        let value = loc.t(key)
        return value == key ? category.title : value
    }
}

private struct GeneratedImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: LocalizationService

    let asset: GeneratedImageAsset
    let onImageUpdated: (UIImage) -> Void
    let onSaveToGallery: (UIImage) -> Bool

    @State private var image: UIImage
    @State private var showingShare = false
    @State private var showingEditor = false
    @State private var saveMessage: String?

    init(
        asset: GeneratedImageAsset,
        onImageUpdated: @escaping (UIImage) -> Void,
        onSaveToGallery: @escaping (UIImage) -> Bool
    ) {
        self.asset = asset
        self.onImageUpdated = onImageUpdated
        self.onSaveToGallery = onSaveToGallery
        _image = State(initialValue: asset.image)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 14)
                    metaBar
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
                        .transition(.opacity)
                        .padding(.bottom, 30)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .navigationTitle(loc.t("gen_result"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc.t("btn_done")) { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { saveToPhotos() } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .accessibilityLabel(loc.t("common_save"))
                    Button { saveToGallery() } label: {
                        Image(systemName: "photo.stack")
                    }
                    .accessibilityLabel(loc.t("gen_gallery"))
                    Button { showingShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(loc.t("gen_action_share"))
                    Button { showingEditor = true } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(loc.t("gen_action_edit"))
                    Button { showingEditor = true } label: {
                        Image(systemName: "paintbrush")
                    }
                    .accessibilityLabel(loc.t("gen_action_draw"))
                }
            }
            .sheet(isPresented: $showingShare) {
                ImageActivityViewController(image: image)
            }
            .fullScreenCover(isPresented: $showingEditor) {
                ImageMarkupEditorView(source: image) { edited in
                    image = edited
                    onImageUpdated(edited)
                }
                .environmentObject(loc)
            }
        }
    }

    private var metaBar: some View {
        HStack(spacing: 10) {
            Label(asset.provider.uppercased(), systemImage: "cpu")
            Label("\(asset.costCredits)", systemImage: "creditcard")
            if let credits = asset.creditsRemaining {
                Label("\(credits)", systemImage: "banknote")
            }
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.white.opacity(0.62))
        .padding(.horizontal, 14)
    }

    private func saveToPhotos() {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        withAnimation { saveMessage = loc.t("gen_saved_photos") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { saveMessage = nil }
        }
    }

    private func saveToGallery() {
        let saved = onSaveToGallery(image)
        withAnimation { saveMessage = saved ? loc.t("gen_saved_gallery") : loc.t("gen_save_failed") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { saveMessage = nil }
        }
    }
}

private final class DrawingCanvasState: ObservableObject {
    let canvasView = PKCanvasView()
}

struct ImageMarkupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: LocalizationService

    let source: UIImage
    let onDone: (UIImage) -> Void

    @StateObject private var canvas = DrawingCanvasState()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = max(180, min(proxy.size.width - 24, proxy.size.height - 48))
                ZStack {
                    Color.black.ignoresSafeArea()

                    ZStack {
                        Image(uiImage: source)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)

                        PencilCanvasRepresentable(canvasView: canvas.canvasView)
                            .frame(width: side, height: side)
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(loc.t("gen_draw"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc.t("btn_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("btn_done")) {
                        onDone(renderEditedImage())
                        dismiss()
                    }
                }
            }
        }
    }

    private func renderEditedImage() -> UIImage {
        let bounds = canvas.canvasView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return source }

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.cgContext.fill(bounds)

            source.draw(in: aspectFitRect(imageSize: source.size, bounds: bounds))
            let drawing = canvas.canvasView.drawing.image(from: bounds, scale: UIScreen.main.scale)
            drawing.draw(in: bounds)
        }
    }

    private func aspectFitRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    let canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 6)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

private struct ImageActivityViewController: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private enum ImageGeneratorError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Image generation returned invalid image data."
    }
}
