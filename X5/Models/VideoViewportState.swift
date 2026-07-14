import Foundation

/// Persisted viewport values for a zoomable video player.
///
/// Gesture-specific deltas stay in the view. This state only stores the
/// committed scale and translation, which keeps its behavior deterministic
/// and straightforward to test.
struct VideoViewportState: Equatable {
    static let minimumScale = 1.0
    static let maximumScale = 4.0

    private(set) var scale = minimumScale
    private(set) var translationX = 0.0
    private(set) var translationY = 0.0

    mutating func applyMagnification(_ magnification: Double) {
        scale = min(max(magnification, Self.minimumScale), Self.maximumScale)

        if scale == Self.minimumScale {
            translationX = 0
            translationY = 0
        }
    }

    mutating func applyTranslation(x: Double, y: Double) {
        guard scale > Self.minimumScale else { return }
        translationX = x
        translationY = y
    }

    mutating func reset() {
        self = VideoViewportState()
    }
}
