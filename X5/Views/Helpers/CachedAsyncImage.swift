import SwiftUI
import UIKit

/// Drop-in replacement for SwiftUI's `AsyncImage` that hits `ImageCache`
/// instead of re-downloading on every appearance. Fetches once, caches on
/// disk, and returns the cached UIImage on subsequent appearances — even
/// across app launches.
///
/// Usage mirrors AsyncImage but with closures for loaded image / placeholder
/// (no `phase.error`-style enum — we fall through to the placeholder on any
/// failure, since views in X5 always render a fallback graphic).
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var loaded = false

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let img = image {
                content(Image(uiImage: img))
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            loaded = true
            return
        }
        let result = await ImageCache.shared.image(for: url)
        await MainActor.run {
            self.image = result
            self.loaded = true
        }
    }
}

/// Convenience for the very common "placeholder is just a ProgressView or
/// blank surface" shape — keeps callsites short.
extension CachedAsyncImage where Placeholder == EmptyView {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.init(url: url, content: content, placeholder: { EmptyView() })
    }
}
