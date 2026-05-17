import SwiftUI
import UIKit

struct ImageGeneratorView: View {
    @EnvironmentObject private var auth: Auth
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedImage: UIImage?
    @State private var shareImage: UIImage?
    @State private var showingShare = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    promptPanel
                    generateButton
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
            .navigationTitle("Create Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShare) {
                if let shareImage {
                    ImageActivityViewController(image: shareImage)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Text("AI")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }

            Text("Generate ad-ready visuals")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Describe a product, offer, scene, or creative idea. X5 returns a square image ready for content and ads.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundColor(.white.opacity(0.66))
        }
        .padding(18)
        .x5ClearGlass(cornerRadius: 20, highlight: 0.13)
    }

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROMPT")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))

            TextField("Premium Instagram ad for a coffee brand, dark studio light, blue glass details", text: $prompt, axis: .vertical)
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
                quickPrompt("Product ad")
                quickPrompt("SMM post")
                quickPrompt("Luxury banner")
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
                Text(isGenerating ? "Generating..." : "Generate image")
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canGenerate ? Color.accentColor : Color.gray.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate || isGenerating)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let generatedImage {
            VStack(alignment: .leading, spacing: 12) {
                Image(uiImage: generatedImage)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Button {
                    shareImage = generatedImage
                    showingShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .x5ClearGlass(cornerRadius: 14, highlight: 0.11)
                }
                .buttonStyle(.plain)
            }
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
            RadialGradient(colors: [Color.accentColor.opacity(0.22), Color.clear],
                           center: .topTrailing, startRadius: 10, endRadius: 280)
                .ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.13, green: 0.33, blue: 0.55).opacity(0.28), Color.clear],
                           center: .bottomLeading, startRadius: 20, endRadius: 320)
                .ignoresSafeArea()
        }
    }

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func quickPrompt(_ text: String) -> some View {
        Button {
            prompt = text
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

    private func generate() async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        promptFocused = false
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let response = try await auth.supabase.generateImage(prompt: cleanPrompt)
            guard let data = Data(base64Encoded: response.imageBase64),
                  let image = UIImage(data: data)
            else {
                throw ImageGeneratorError.invalidImage
            }
            generatedImage = image
            DiagnosticLogger.log(event: "image_generated")
        } catch {
            DiagnosticLogger.log(event: "image_generation_failed", extra: [
                "summary": error.localizedDescription
            ])
            errorMessage = error.localizedDescription
        }
    }
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
