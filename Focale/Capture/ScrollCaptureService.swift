import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

// MARK: - Capture défilante (F12) : bandes + défilement programmé + assemblage.
// Vertical uniquement. Le défilement programmé exige la permission Accessibilité.

// Sans état mutable : partage inter-threads sûr.
final class ScrollCaptureService: @unchecked Sendable {
    private let capture = CaptureServiceBridge()

    /// rect : points, origine haut-gauche de l'écran.
    /// progress : (bandes capturées) — appelé hors acteur principal.
    func run(
        displayID: CGDirectDisplayID,
        rect: CGRect,
        scale: CGFloat
    ) async throws -> CGImage {
        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            throw ScrollError.accessibilityDenied
        }
        let bandHeight = min(rect.height, 1200)
        let band = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bandHeight)
        let overlap: CGFloat = 140
        let step = max(bandHeight - overlap, 100)
        let maxBands = 15

        var bands: [CGImage] = []
        var previousHash: Int?
        var repeats = 0

        for index in 0..<maxBands {
            try Task.checkCancellation()
            let image = try await capture.captureRegion(displayID: displayID, rect: band, scale: scale)
            let hash = thumbHash(image)
            if hash == previousHash {
                repeats += 1
                if repeats >= 2 { break }
            } else {
                repeats = 0
                bands.append(image)
            }
            previousHash = hash
            guard index < maxBands - 1 else { break }
            scrollDown(points: step)
            try await Task.sleep(for: .milliseconds(450))
        }
        guard let first = bands.first else {
            throw ScrollError.noContent
        }
        return stitch(bands: bands, stepPoints: step, scale: scale) ?? first
    }

    private func scrollDown(points: CGFloat) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -Int32(points.rounded()),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Assemblage à pas nominal (défilement programmé exact, pas de dérive).
    private func stitch(bands: [CGImage], stepPoints: CGFloat, scale: CGFloat) -> CGImage? {
        guard let first = bands.first else { return nil }
        let width = first.width
        let bandHeight = first.height
        let step = Int((stepPoints * scale).rounded())
        let totalHeight = step * (bands.count - 1) + bandHeight
        guard width > 0, totalHeight > 0,
              let context = CGContext(
                  data: nil, width: width, height: totalHeight,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // CGContext : origine bas-gauche — la bande i se dessine en partant du haut.
        for (index, band) in bands.enumerated() {
            let yFromTop = index * step
            context.draw(band, in: CGRect(
                x: 0,
                y: totalHeight - yFromTop - band.height,
                width: band.width,
                height: band.height
            ))
        }
        return context.makeImage()
    }

    /// Empreinte grossière (64 px) pour détecter la fin du contenu.
    private func thumbHash(_ image: CGImage) -> Int {
        let width = 64
        let height = max(Int(64 * CGFloat(image.height) / CGFloat(max(image.width, 1))), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image.width ^ image.height }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return image.width ^ image.height }
        var hash = 5381
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var index = 0
        while index < width * height * 4 {
            hash = ((hash << 5) &+ hash) &+ Int(bytes[index])
            index += 16
        }
        return hash
    }
}

// MARK: - Pont non isolé vers la capture (le service défile hors acteur principal).

private final class CaptureServiceBridge {
    func captureRegion(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let bundleID = Bundle.main.bundleIdentifier
        let excluded = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.capturesAudio = false
        config.width = max(Int((CGFloat(display.width) * scale).rounded()), 1)
        config.height = max(Int((CGFloat(display.height) * scale).rounded()), 1)
        let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let cropped = Images.crop(full, toPoints: rect, scale: scale) else {
            throw CaptureError.cropFailed
        }
        return cropped
    }
}

enum ScrollError: LocalizedError {
    case accessibilityDenied
    case noContent

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "La capture défilante exige la permission Accessibilité (Réglages Système → Confidentialité et sécurité → Accessibilité)."
        case .noContent:
            "Aucun contenu capturé pendant le défilement."
        }
    }
}
