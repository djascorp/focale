import AVFoundation
import Foundation
import ScreenCaptureKit

// MARK: - Enregistrement d'écran : SCStream → MP4 (H.264), audio système optionnel (F11).

// Tout l'état mutable est protégé par le verrou : partage inter-threads sûr.
final class RecorderService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var streamError: Error?
    private var recording = false

    private let videoQueue = DispatchQueue(label: "focale.recorder.video")
    private let audioQueue = DispatchQueue(label: "focale.recorder.audio")

    var isRecording: Bool {
        lock.withLock { recording }
    }

    /// Dimensions paires exigées par H.264.
    static func evenPixelSize(_ size: CGSize) -> CGSize {
        CGSize(width: max((Int(size.width) / 2) * 2, 2), height: max((Int(size.height) / 2) * 2, 2))
    }

    func start(
        displayID: CGDirectDisplayID,
        windowID: CGWindowID?,
        pixelSize: CGSize,
        capturesAudio: Bool,
        url: URL
    ) async throws {
        let size = Self.evenPixelSize(pixelSize)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        if let windowID, let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.capturesAudio = capturesAudio
        if capturesAudio {
            config.sampleRate = 48000
            config.channelCount = 2
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if capturesAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        }
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerFailed
        }
        lock.withLock {
            self.stream = stream
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.outputURL = url
            self.sessionStarted = false
            self.streamError = nil
            self.recording = true
        }
        try await stream.startCapture()
    }

    /// Arrête et finalise. Retourne l'URL du fichier, ou nil si annulé/échoué.
    func stop() async -> URL? {
        let current: SCStream? = lock.withLock {
            recording = false
            let value = stream
            stream = nil
            return value
        }
        guard current != nil else { return nil }
        try? await current?.stopCapture()
        let (writer, video, audio, url): (AVAssetWriter?, AVAssetWriterInput?, AVAssetWriterInput?, URL?) = lock.withLock {
            let tuple = (self.writer, self.videoInput, self.audioInput, self.outputURL)
            self.writer = nil
            self.videoInput = nil
            self.audioInput = nil
            self.outputURL = nil
            return tuple
        }
        video?.markAsFinished()
        audio?.markAsFinished()
        await writer?.finishWriting()
        let failed: Bool = lock.withLock { streamError != nil } || writer?.error != nil || writer?.status != .completed
        return failed ? nil : url
    }

    // MARK: SCStreamOutput (files secondaires, état protégé par verrou).

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        lock.withLock {
            guard recording, let writer else { return }
            switch type {
            case .screen:
                guard let input = videoInput, input.isReadyForMoreMediaData else { return }
                if !sessionStarted {
                    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    sessionStarted = true
                }
                input.append(sampleBuffer)
            case .audio:
                guard sessionStarted, let input = audioInput, input.isReadyForMoreMediaData else { return }
                input.append(sampleBuffer)
            @unknown default:
                break
            }
        }
    }

    // MARK: SCStreamDelegate.

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { streamError = error }
    }
}

enum RecorderError: LocalizedError {
    case writerFailed

    var errorDescription: String? {
        "Impossible de démarrer l'enregistrement vidéo."
    }
}
