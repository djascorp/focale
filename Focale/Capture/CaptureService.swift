import AppKit
import ScreenCaptureKit

// MARK: - Cible de capture : écran + échelle + repère global AppKit.

struct DisplayCaptureTarget {
    let displayID: CGDirectDisplayID
    let scale: CGFloat
    let frame: CGRect
}

// MARK: - Service de capture ScreenCaptureKit.
//
// Stratégie déterministe : capture plein écran puis recadrage exact en pixels.
// Aucune ambiguïté d'unités/origine sur les zones partielles.

@MainActor
final class CaptureService {
    private var content: SCShareableContent?

    static func target(for screen: NSScreen) -> DisplayCaptureTarget? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return DisplayCaptureTarget(
            displayID: CGDirectDisplayID(number.uint32Value),
            scale: screen.backingScaleFactor,
            frame: screen.frame
        )
    }

    /// Précharge le contenu partageable pour une capture instantanée (§9.6.4).
    func preload() async {
        content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func refresh() async {
        content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Fenêtres de Focale à exclure de la capture (§9.6.7).
    private func ownWindows() -> [SCWindow] {
        let bundleID = Bundle.main.bundleIdentifier
        return (content?.windows ?? []).filter { $0.owningApplication?.bundleIdentifier == bundleID }
    }

    private func baseConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.capturesAudio = false
        return config
    }

    /// Capture plein écran en pleine résolution (SCDisplay.width/height sont en points).
    func captureFullDisplay(displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        await refresh()
        guard let display = content?.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows())
        let config = baseConfig()
        config.width = max(Int((CGFloat(display.width) * scale).rounded()), 1)
        config.height = max(Int((CGFloat(display.height) * scale).rounded()), 1)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// rect : points, origine haut-gauche de l'écran.
    func captureRegion(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat) async throws -> CGImage {
        let full = try await captureFullDisplay(displayID: displayID, scale: scale)
        guard let cropped = Images.crop(full, toPoints: rect, scale: scale) else {
            throw CaptureError.cropFailed
        }
        return cropped
    }

    func captureDisplay(id: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        try await captureFullDisplay(displayID: id, scale: scale)
    }

    func captureWindow(windowID: CGWindowID, pixelSize: CGSize) async throws -> CGImage {
        await refresh()
        guard let window = content?.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = baseConfig()
        config.width = max(Int(pixelSize.width.rounded()), 1)
        config.height = max(Int(pixelSize.height.rounded()), 1)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Écran introuvable."
        case .windowNotFound: "Fenêtre introuvable."
        case .cropFailed: "Impossible d'extraire la zone sélectionnée."
        }
    }
}
