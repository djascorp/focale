import AVFoundation
import CoreImage
import Foundation
import UniformTypeIdentifiers

// MARK: - Post-traitements vidéo déterministes : recadrage, miniature, GIF.

enum VideoService {
    private static let ciContext = CIContext()

    /// Recadre une vidéo en ré-encodant (CIImage origine bas-gauche : inversion verticale).
    /// crop : points, origine haut-gauche, dans le repère de l'enregistrement.
    static func transcodeCrop(input: URL, crop: CGRect, scale: CGFloat, output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        var pixels = CGRect(
            x: (crop.minX * scale).rounded(),
            y: (crop.minY * scale).rounded(),
            width: (crop.width * scale).rounded(),
            height: (crop.height * scale).rounded()
        )
        // Dimensions paires pour H.264.
        pixels.size.width = CGFloat(max((Int(pixels.width) / 2) * 2, 2))
        pixels.size.height = CGFloat(max((Int(pixels.height) / 2) * 2, 2))
        pixels = pixels.intersection(CGRect(origin: .zero, size: naturalSize))
        guard !pixels.isNull, pixels.width >= 2, pixels.height >= 2 else {
            throw VideoError.invalidCrop
        }
        let flipped = CGRect(
            x: pixels.minX,
            y: naturalSize.height - pixels.maxY,
            width: pixels.width,
            height: pixels.height
        )

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(readerOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(output)
            audioOutput = output
        }

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixels.width),
            AVVideoHeightKey: Int(pixels.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
        ])
        writer.add(videoInput)
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            writer.add(input)
            audioInput = input
        }
        guard writer.startWriting() else {
            throw writer.error ?? VideoError.transcodeFailed
        }
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(pixels.width),
            kCVPixelBufferHeightKey as String: Int(pixels.height),
        ])
        while let sample = readerOutput.copyNextSampleBuffer() {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let source = CMSampleBufferGetImageBuffer(sample) else { continue }
            let cropped = CIImage(cvPixelBuffer: source).cropped(to: flipped)
            guard let pool = adaptor.pixelBufferPool else { continue }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            ciContext.render(cropped, to: buffer)
            adaptor.append(buffer, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
        }
        videoInput.markAsFinished()
        if let audioOutput, let audioInput {
            while let sample = audioOutput.copyNextSampleBuffer() {
                while !audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(10))
                }
                audioInput.append(sample)
            }
            audioInput.markAsFinished()
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? VideoError.transcodeFailed
        }
    }

    /// Miniature pour l'historique et la miniature flottante.
    static func thumbnail(for url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        return try? await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
    }

    static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)) ?? .zero
        return duration.seconds.isFinite ? duration.seconds : 0
    }

    /// Convertit en GIF (largeur plafonnée, durée plafonnée à 10 s).
    static func convertToGIF(input: URL, output: URL, maxWidth: CGFloat = 480, frameInterval: Double = 0.12) async throws {
        let asset = AVURLAsset(url: input)
        let duration = min((try? await asset.load(.duration).seconds) ?? 0, 10)
        guard duration > 0 else { throw VideoError.noVideoTrack }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: frameInterval, preferredTimescale: 600)

        try? FileManager.default.removeItem(at: output)
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.gif.identifier as CFString, 0, nil
        ) else { throw VideoError.transcodeFailed }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFLoopCount as String: 0,
        ]] as CFDictionary)

        var time = 0.0
        while time < duration {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameInterval,
            ]] as CFDictionary)
            time += frameInterval
        }
        guard CGImageDestinationFinalize(destination) else {
            throw VideoError.transcodeFailed
        }
    }
}

enum VideoError: LocalizedError {
    case noVideoTrack
    case invalidCrop
    case transcodeFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "Aucune piste vidéo trouvée."
        case .invalidCrop: "Zone de recadrage invalide."
        case .transcodeFailed: "La conversion vidéo a échoué."
        }
    }
}
