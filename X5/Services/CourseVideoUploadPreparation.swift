import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import SessionExporter

struct CourseVideoEncodingPlan: Equatable {
    let width: Int
    let height: Int
    let videoBitRate: Int
    let audioBitRate: Int
}

enum CourseVideoExportStrategy: String, Equatable, Sendable {
    case nextLevel = "nextlevel"
    case avFoundation = "avfoundation"
}

struct CourseVideoExportDiagnostic: Equatable, Sendable {
    let strategy: CourseVideoExportStrategy
    let underlyingCode: Int

    var code: String {
        "\(strategy.rawValue).\(underlyingCode)"
    }

    init(strategy: CourseVideoExportStrategy, error: Error) {
        self.strategy = strategy
        underlyingCode = (error as NSError).code
    }
}

enum CourseVideoUploadPreparationError: Error, Equatable, LocalizedError {
    case unreadableFile
    case missingVideoTrack
    case invalidVideo
    case videoTooLong
    case exportFailed(
        primary: CourseVideoExportDiagnostic,
        fallback: CourseVideoExportDiagnostic
    )
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
        case let .exportFailed(primary, fallback):
            return """
            Не удалось подготовить видео. Исходник сохранён — можно повторить \
            без повторного выбора файла. Код: \(primary.code) / \(fallback.code).
            """
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

    static let uploadGuidance = "До 47 МБ загружается напрямую. Большие файлы автоматически сжимаются примерно до 45 МБ и затем отправляются возобновляемой загрузкой. Очень длинное видео лучше разделить на уроки."

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

struct CourseVideoExportRequest {
    let sourceURL: URL
    let sourceAsset: AVAsset
    let sourceDurationSeconds: Double
    let outputURL: URL
    let videoComposition: AVVideoComposition
    let plan: CourseVideoEncodingPlan
}

private enum CourseVideoExporterInternalError:
    Int,
    Error,
    CustomNSError
{
    case missingCompletedURL = 1_001
    case preparedOutputInvalid = 1_002
    case nativePresetUnavailable = 1_003
    case nativeMP4Unavailable = 1_004
    case nativeExportIncomplete = 1_005

    static var errorDomain: String {
        "X5.CourseVideoExporter"
    }

    var errorCode: Int {
        rawValue
    }
}

final class CourseVideoUploadPreparer {
    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias ExportOperation = (
        CourseVideoExportRequest,
        @escaping ProgressHandler
    ) async throws -> Void

    private let primaryExporter: ExportOperation
    private let fallbackExporter: ExportOperation

    init(
        primaryExporter: ExportOperation? = nil,
        fallbackExporter: ExportOperation? = nil
    ) {
        self.primaryExporter = primaryExporter ?? { request, progress in
            try await Self.exportWithNextLevel(
                request,
                progress: progress
            )
        }
        self.fallbackExporter = fallbackExporter ?? { request, progress in
            try await Self.exportWithAVFoundation(
                request,
                progress: progress
            )
        }
    }

    func prepare(
        fileURL: URL,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> URL {
        let sourceSize = try Self.fileSize(at: fileURL)
        guard CourseVideoUploadPolicy.requiresTranscoding(
            fileSizeBytes: sourceSize
        ) else {
            progress(1)
            return fileURL
        }

        let sourceAsset = AVURLAsset(url: fileURL)
        let sourceDurationTime = try await sourceAsset.load(.duration)
        let sourceDuration = try Self.validatedDurationSeconds(
            sourceDurationTime
        )
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
            if (try? await Self.isValidPreparedFile(
                outputURL,
                sourceDurationSeconds: sourceDuration
            )) == true {
                progress(1)
                return outputURL
            }
            try? FileManager.default.removeItem(at: outputURL)
        }

        let request = CourseVideoExportRequest(
            sourceURL: fileURL,
            sourceAsset: sourceAsset,
            sourceDurationSeconds: sourceDuration,
            outputURL: outputURL,
            videoComposition: try makeVideoComposition(
                videoTrack: videoTrack,
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                nominalFrameRate: nominalFrameRate,
                duration: sourceDurationTime,
                plan: plan
            ),
            plan: plan
        )

        let primaryDiagnostic: CourseVideoExportDiagnostic
        do {
            try await primaryExporter(request) { fraction in
                progress(Self.boundedProgress(fraction) * 0.49)
            }
            guard try await Self.isValidPreparedFile(
                outputURL,
                sourceDurationSeconds: sourceDuration
            ) else {
                throw CourseVideoExporterInternalError.preparedOutputInvalid
            }
            progress(1)
            return outputURL
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: outputURL)
                throw CancellationError()
            }
            primaryDiagnostic = CourseVideoExportDiagnostic(
                strategy: .nextLevel,
                error: error
            )
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try await fallbackExporter(request) { fraction in
                progress(0.5 + (Self.boundedProgress(fraction) * 0.49))
            }
            guard try await Self.isValidPreparedFile(
                outputURL,
                sourceDurationSeconds: sourceDuration
            ) else {
                throw CourseVideoExporterInternalError.preparedOutputInvalid
            }
            progress(1)
            return outputURL
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: outputURL)
                throw CancellationError()
            }
            try? FileManager.default.removeItem(at: outputURL)
            throw CourseVideoUploadPreparationError.exportFailed(
                primary: primaryDiagnostic,
                fallback: CourseVideoExportDiagnostic(
                    strategy: .avFoundation,
                    error: error
                )
            )
        }
    }

    private static func exportWithNextLevel(
        _ request: CourseVideoExportRequest,
        progress: @escaping ProgressHandler
    ) async throws {
        let exporter = NextLevelSessionExporter(withAsset: request.sourceAsset)
        exporter.outputURL = request.outputURL
        exporter.outputFileType = .mp4
        exporter.optimizeForNetworkUse = true
        exporter.preserveHDR = false
        exporter.videoComposition = request.videoComposition
        exporter.videoOutputConfiguration = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: request.plan.width),
            AVVideoHeightKey: NSNumber(value: request.plan.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: NSNumber(
                    value: request.plan.videoBitRate
                ),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: NSNumber(value: 30)
            ]
        ]
        exporter.audioOutputConfiguration = [
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
            AVEncoderBitRateKey: NSNumber(value: request.plan.audioBitRate),
            AVNumberOfChannelsKey: NSNumber(value: 2),
            AVSampleRateKey: NSNumber(value: 44_100)
        ]

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
        guard completedURL?.standardizedFileURL
            == request.outputURL.standardizedFileURL
        else {
            throw CourseVideoExporterInternalError.missingCompletedURL
        }
    }

    private static func exportWithAVFoundation(
        _ request: CourseVideoExportRequest,
        progress: @escaping ProgressHandler
    ) async throws {
        let compatiblePresets = Set(
            AVAssetExportSession.exportPresets(
                compatibleWith: request.sourceAsset
            )
        )
        let presets = [
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality
        ].filter(compatiblePresets.contains)
        guard !presets.isEmpty else {
            throw CourseVideoExporterInternalError.nativePresetUnavailable
        }

        var lastError: Error?
        for (index, preset) in presets.enumerated() {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: request.outputURL)
            let attemptStart = Double(index) / Double(presets.count)
            let attemptSpan = 1 / Double(presets.count)

            do {
                try await exportWithAVFoundation(
                    request,
                    preset: preset
                ) { fraction in
                    progress(
                        attemptStart
                            + (boundedProgress(fraction) * attemptSpan)
                    )
                }
                if try await isValidPreparedFile(
                    request.outputURL,
                    sourceDurationSeconds: request.sourceDurationSeconds
                ) {
                    return
                }
                lastError =
                    CourseVideoExporterInternalError.preparedOutputInvalid
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
            try? FileManager.default.removeItem(at: request.outputURL)
        }

        throw lastError
            ?? CourseVideoExporterInternalError.nativeExportIncomplete
    }

    private static func exportWithAVFoundation(
        _ request: CourseVideoExportRequest,
        preset: String,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let exporter = AVAssetExportSession(
            asset: request.sourceAsset,
            presetName: preset
        ) else {
            throw CourseVideoExporterInternalError.nativePresetUnavailable
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            throw CourseVideoExporterInternalError.nativeMP4Unavailable
        }

        exporter.outputURL = request.outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.fileLengthLimit = CourseVideoUploadPolicy.transcodeTargetBytes
        exporter.videoComposition = request.videoComposition
        exporter.directoryForTemporaryFiles =
            request.outputURL.deletingLastPathComponent()

        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { progressTask.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(
                            throwing: exporter.error
                                ?? CourseVideoExporterInternalError
                                    .nativeExportIncomplete
                        )
                    default:
                        continuation.resume(
                            throwing: CourseVideoExporterInternalError
                                .nativeExportIncomplete
                        )
                    }
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }
        progress(1)
    }

    private static func isValidPreparedFile(
        _ fileURL: URL,
        sourceDurationSeconds: Double
    ) async throws -> Bool {
        let size = try fileSize(at: fileURL)
        let outputAsset = AVURLAsset(url: fileURL)
        guard let videoTrack = try await outputAsset.loadTracks(
            withMediaType: .video
        ).first,
              try await trackUsesCodec(
                  videoTrack,
                  allowedSubtypes: [kCMVideoCodecType_H264]
              )
        else {
            return false
        }
        let audioTracks = try await outputAsset.loadTracks(
            withMediaType: .audio
        )
        for audioTrack in audioTracks {
            guard try await trackUsesCodec(
                audioTrack,
                allowedSubtypes: [kAudioFormatMPEG4AAC]
            ) else {
                return false
            }
        }
        let duration = try await durationSeconds(of: outputAsset)
        return CourseVideoUploadPolicy.isAcceptablePreparedOutput(
            fileSizeBytes: size,
            sourceDurationSeconds: sourceDurationSeconds,
            outputDurationSeconds: duration
        )
    }

    private static func trackUsesCodec(
        _ track: AVAssetTrack,
        allowedSubtypes: Set<FourCharCode>
    ) async throws -> Bool {
        let descriptions = try await track.load(.formatDescriptions)
        return descriptions.contains {
            allowedSubtypes.contains(
                CMFormatDescriptionGetMediaSubType($0)
            )
        }
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

    private static func fileSize(at url: URL) throws -> Int64 {
        guard let size = try url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize else {
            throw CourseVideoUploadPreparationError.unreadableFile
        }
        return Int64(size)
    }

    private static func durationSeconds(of asset: AVAsset) async throws -> Double {
        let duration = try await asset.load(.duration)
        return try validatedDurationSeconds(duration)
    }

    private static func validatedDurationSeconds(
        _ duration: CMTime
    ) throws -> Double {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw CourseVideoUploadPreparationError.invalidVideo
        }
        return seconds
    }

    private static func boundedProgress(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}
