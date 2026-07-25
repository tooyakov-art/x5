import AVFoundation
import AudioToolbox
import Foundation
import SessionExporter

struct CourseVideoEncodingPlan: Equatable {
    let width: Int
    let height: Int
    let videoBitRate: Int
    let audioBitRate: Int
}

enum CourseVideoUploadPreparationError: Error, Equatable, LocalizedError {
    case unreadableFile
    case missingVideoTrack
    case invalidVideo
    case videoTooLong
    case exportFailed
    case preparedFileInvalid

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Не удалось прочитать выбранное видео."
        case .missingVideoTrack:
            return "В выбранном файле не найден видеоряд."
        case .invalidVideo:
            return "Не удалось определить параметры выбранного видео."
        case .videoTooLong:
            return "Видео слишком длинное для автоматической подготовки. Разделите его на несколько уроков."
        case .exportFailed:
            return "Не удалось уменьшить видео перед загрузкой. Попробуйте выбрать другое видео."
        case .preparedFileInvalid:
            return "Не удалось подготовить видео целиком. Попробуйте более короткий файл."
        }
    }
}

enum CourseVideoUploadPolicy {
    /// Supabase Free has a global 50 MB Storage limit. A bucket-level value
    /// cannot raise it, so uploads need headroom below the server boundary.
    static let serverLimitBytes: Int64 = 50 * 1_024 * 1_024
    static let directUploadLimitBytes: Int64 = 47_000_000
    static let transcodeTargetBytes: Int64 = 45_000_000

    private static let targetPayloadFraction = 0.90
    private static let audioBitRate = 48_000
    private static let minimumVideoBitRate = 64_000
    private static let maximumVideoBitRate = 2_800_000

    static func requiresTranscoding(fileSizeBytes: Int64) -> Bool {
        fileSizeBytes > directUploadLimitBytes
    }

    static func makeEncodingPlan(
        durationSeconds: Double,
        presentationWidth: Double,
        presentationHeight: Double
    ) throws -> CourseVideoEncodingPlan {
        guard durationSeconds.isFinite,
              durationSeconds > 0,
              presentationWidth.isFinite,
              presentationHeight.isFinite,
              presentationWidth > 0,
              presentationHeight > 0
        else {
            throw CourseVideoUploadPreparationError.invalidVideo
        }

        let totalBitRate = Int(
            (Double(transcodeTargetBytes) * 8 * targetPayloadFraction)
                / durationSeconds
        )
        let videoBitRate = min(
            maximumVideoBitRate,
            totalBitRate - audioBitRate
        )
        guard videoBitRate >= minimumVideoBitRate else {
            throw CourseVideoUploadPreparationError.videoTooLong
        }

        let maximumLongSide: Double
        switch videoBitRate {
        case 1_000_000...:
            maximumLongSide = 1_280
        case 350_000...:
            maximumLongSide = 960
        default:
            maximumLongSide = 640
        }

        let sourceLongSide = max(presentationWidth, presentationHeight)
        let scale = min(1, maximumLongSide / sourceLongSide)
        let width = evenDimension(presentationWidth * scale)
        let height = evenDimension(presentationHeight * scale)

        return CourseVideoEncodingPlan(
            width: width,
            height: height,
            videoBitRate: videoBitRate,
            audioBitRate: audioBitRate
        )
    }

    static func isAcceptablePreparedOutput(
        fileSizeBytes: Int64,
        sourceDurationSeconds: Double,
        outputDurationSeconds: Double
    ) -> Bool {
        guard fileSizeBytes > 0,
              fileSizeBytes <= directUploadLimitBytes,
              sourceDurationSeconds.isFinite,
              outputDurationSeconds.isFinite,
              sourceDurationSeconds > 0,
              outputDurationSeconds > 0
        else {
            return false
        }

        let durationTolerance = max(1, sourceDurationSeconds * 0.01)
        return abs(sourceDurationSeconds - outputDurationSeconds) <= durationTolerance
    }

    private static func evenDimension(_ value: Double) -> Int {
        max(2, Int(value.rounded(.down)) / 2 * 2)
    }
}

enum CourseVideoCompositionTransform {
    static func make(
        sourceSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetSize: CGSize
    ) throws -> CGAffineTransform {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0
        else {
            throw CourseVideoUploadPreparationError.invalidVideo
        }

        let transformedRect = CGRect(
            origin: .zero,
            size: sourceSize
        ).applying(preferredTransform)
        let presentationWidth = abs(transformedRect.width)
        let presentationHeight = abs(transformedRect.height)
        guard presentationWidth > 0, presentationHeight > 0 else {
            throw CourseVideoUploadPreparationError.invalidVideo
        }

        var normalized = preferredTransform
        normalized.tx -= transformedRect.minX
        normalized.ty -= transformedRect.minY

        let scale = min(
            targetSize.width / presentationWidth,
            targetSize.height / presentationHeight
        )
        let offsetX = (targetSize.width - (presentationWidth * scale)) / 2
        let offsetY = (targetSize.height - (presentationHeight * scale)) / 2

        // Apply the normalized orientation first, followed by uniform scaling
        // and centering. Building the coefficients directly avoids ambiguous
        // transform-concatenation order for rotated portrait videos.
        return CGAffineTransform(
            a: normalized.a * scale,
            b: normalized.b * scale,
            c: normalized.c * scale,
            d: normalized.d * scale,
            tx: (normalized.tx * scale) + offsetX,
            ty: (normalized.ty * scale) + offsetY
        )
    }
}

final class CourseVideoUploadPreparer {
    typealias ProgressHandler = @Sendable (Double) -> Void

    func prepare(
        fileURL: URL,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> URL {
        let sourceSize = try fileSize(at: fileURL)
        guard CourseVideoUploadPolicy.requiresTranscoding(
            fileSizeBytes: sourceSize
        ) else {
            progress(1)
            return fileURL
        }

        let sourceAsset = AVURLAsset(url: fileURL)
        let sourceDurationTime = try await sourceAsset.load(.duration)
        let sourceDuration = try validatedDurationSeconds(sourceDurationTime)
        guard let videoTrack = try await sourceAsset.loadTracks(
            withMediaType: .video
        ).first else {
            throw CourseVideoUploadPreparationError.missingVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let transformedRect = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform)
        let presentationWidth = Double(abs(transformedRect.width))
        let presentationHeight = Double(abs(transformedRect.height))
        let plan = try CourseVideoUploadPolicy.makeEncodingPlan(
            durationSeconds: sourceDuration,
            presentationWidth: presentationWidth,
            presentationHeight: presentationHeight
        )

        let outputURL = CourseVideoStaging.preparedUploadURL(for: fileURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            if (try? await isValidPreparedFile(
                outputURL,
                sourceDurationSeconds: sourceDuration
            )) == true {
                progress(1)
                return outputURL
            }
            try? FileManager.default.removeItem(at: outputURL)
        }

        let exporter = NextLevelSessionExporter(withAsset: sourceAsset)
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.optimizeForNetworkUse = true
        exporter.preserveHDR = false
        exporter.videoComposition = try makeVideoComposition(
            videoTrack: videoTrack,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            nominalFrameRate: nominalFrameRate,
            duration: sourceDurationTime,
            plan: plan
        )
        exporter.videoOutputConfiguration = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: plan.width),
            AVVideoHeightKey: NSNumber(value: plan.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: NSNumber(value: plan.videoBitRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: NSNumber(value: 30)
            ]
        ]
        exporter.audioOutputConfiguration = [
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
            AVEncoderBitRateKey: NSNumber(value: plan.audioBitRate),
            AVNumberOfChannelsKey: NSNumber(value: 2),
            AVSampleRateKey: NSNumber(value: 44_100)
        ]

        do {
            var completedURL: URL?
            for try await event in exporter.exportAsync() {
                switch event {
                case .progress(let fraction):
                    progress(Double(fraction))
                case .completed(let url):
                    completedURL = url
                @unknown default:
                    break
                }
            }
            guard completedURL != nil else {
                throw CourseVideoUploadPreparationError.exportFailed
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw CourseVideoUploadPreparationError.exportFailed
        }

        guard try await isValidPreparedFile(
            outputURL,
            sourceDurationSeconds: sourceDuration
        ) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CourseVideoUploadPreparationError.preparedFileInvalid
        }

        progress(1)
        return outputURL
    }

    private func isValidPreparedFile(
        _ fileURL: URL,
        sourceDurationSeconds: Double
    ) async throws -> Bool {
        let size = try fileSize(at: fileURL)
        let outputAsset = AVURLAsset(url: fileURL)
        guard !(try await outputAsset.loadTracks(
            withMediaType: .video
        )).isEmpty else {
            return false
        }
        let duration = try await durationSeconds(of: outputAsset)
        return CourseVideoUploadPolicy.isAcceptablePreparedOutput(
            fileSizeBytes: size,
            sourceDurationSeconds: sourceDurationSeconds,
            outputDurationSeconds: duration
        )
    }

    private func makeVideoComposition(
        videoTrack: AVAssetTrack,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        nominalFrameRate: Float,
        duration: CMTime,
        plan: CourseVideoEncodingPlan
    ) throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: plan.width, height: plan.height)
        let boundedFrameRate: Int32
        if nominalFrameRate.isFinite, nominalFrameRate > 0 {
            boundedFrameRate = Int32(
                min(max(nominalFrameRate.rounded(), 1), 30)
            )
        } else {
            boundedFrameRate = 30
        }
        composition.frameDuration = CMTime(
            value: 1,
            timescale: boundedFrameRate
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: videoTrack
        )
        layerInstruction.setTransform(
            try CourseVideoCompositionTransform.make(
                sourceSize: naturalSize,
                preferredTransform: preferredTransform,
                targetSize: composition.renderSize
            ),
            at: .zero
        )
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        return composition
    }

    private func fileSize(at url: URL) throws -> Int64 {
        guard let size = try url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize else {
            throw CourseVideoUploadPreparationError.unreadableFile
        }
        return Int64(size)
    }

    private func durationSeconds(of asset: AVAsset) async throws -> Double {
        let duration = try await asset.load(.duration)
        return try validatedDurationSeconds(duration)
    }

    private func validatedDurationSeconds(_ duration: CMTime) throws -> Double {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw CourseVideoUploadPreparationError.invalidVideo
        }
        return seconds
    }
}
