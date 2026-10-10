import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Notifications vers les scènes SwiftUI (la barre des menus est toujours vivante).

extension Notification.Name {
    static let focaleOpenHistory = Notification.Name("focale.openHistory")
    static let focaleOpenGallery = Notification.Name("focale.openGallery")
}

// MARK: - Dernière capture répétable (F4).

struct LastCapture {
    let displayID: CGDirectDisplayID
    let rect: CGRect
    let scale: CGFloat
}

// MARK: - Chef d'orchestre : raccourcis → panneaux → capture → destination → miniature.

@Observable
@MainActor
final class CaptureSession {
    let appState: AppState
    private let hotkeys = HotKeyService()
    private let capture = CaptureService()
    private let editor = EditorWindowController()
    private let onboarding = OnboardingWindowController()

    var countdown: Int?
    var isActive = false
    private(set) var lastCapture: LastCapture?

    private var started = false
    private var overlays: [OverlayController] = []
    private var barPanel: CaptureBarPanel?
    private var toastPanel: ToastPanel?
    private var frontApp: NSRunningApplication?
    private var captureTask: Task<Void, Never>?

    private let recorder = RecorderService()
    private let scroller = ScrollCaptureService()
    var isRecording = false
    private var recordingPanel: FloatingStatusPanel?
    private var recordingCrop: CGRect?
    private var recordingScale: CGFloat = 2
    private var recordingFileName = ""
    private var scrollPanel: FloatingStatusPanel?
    private var scrollTask: Task<Void, Never>?

    var canRepeatLast: Bool { lastCapture != nil }

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "focale.hasOnboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "focale.hasOnboarded") }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: Démarrage.

    func start() {
        guard !started else { return }
        started = true
        registerHotkeys()
        appState.settings.onShortcutsChanged = { [weak self] in
            self?.registerHotkeys()
        }
        FocaleIntentHandler.shared.session = self
        if OnboardingPolicy.shouldShowWelcome(hasOnboarded: hasOnboarded) {
            onboarding.show(settings: appState.settings, startPage: 0) { [weak self] in
                self?.hasOnboarded = true
            }
        }
    }

    func registerHotkeys() {
        hotkeys.unregisterAll()
        let settings = appState.settings
        hotkeys.register(shortcut: settings.mainShortcut) { [weak self] in self?.beginCapture() }
        hotkeys.register(shortcut: settings.historyShortcut) {
            NotificationCenter.default.post(name: .focaleOpenHistory, object: nil)
        }
        hotkeys.register(shortcut: settings.repeatShortcut) { [weak self] in self?.repeatLast() }
    }

    // MARK: Session de capture.

    func beginCapture() {
        guard !isActive, !isRecording else { return }
        switch OnboardingPolicy.captureGate(screenCaptureGranted: CGPreflightScreenCaptureAccess()) {
        case .proceed:
            break
        case .showRecovery(let dismissWhenGranted):
            onboarding.show(
                settings: appState.settings,
                startPage: 1,
                dismissWhenGranted: dismissWhenGranted
            ) { [weak self] in
                self?.hasOnboarded = true
            }
            return
        }
        isActive = true
        frontApp = NSWorkspace.shared.frontmostApplication
        hideToast()
        Task { await capture.preload() }
        showOverlays()
        showBar()
        NSApp.activate(ignoringOtherApps: true)
        // La barre prend le clavier (1-5, T, R, C, Entrée, Échap) ; l'overlay
        // reste cliquable à la souris même sans être fenêtre clé.
        if let barPanel {
            barPanel.makeKeyAndOrderFront(nil)
        } else {
            let mouse = NSEvent.mouseLocation
            let keyPanel = overlays.first { $0.screen.frame.contains(mouse) }?.panel ?? overlays.first?.panel
            keyPanel?.makeKeyAndOrderFront(nil)
        }
    }

    func cancel() {
        guard isActive else { return }
        if isRecording {
            stopRecording()
        } else {
            teardown()
        }
    }

    private func teardown() {
        captureTask?.cancel()
        captureTask = nil
        scrollTask?.cancel()
        scrollTask = nil
        countdown = nil
        saveBarPosition()
        overlays.forEach { $0.hide() }
        overlays.removeAll()
        barPanel?.orderOut(nil)
        barPanel = nil
        hideScrollPanel()
        isActive = false
        reactivateFrontApp()
    }

    private func reactivateFrontApp() {
        if let app = frontApp, app != NSRunningApplication.current {
            app.activate()
        }
        frontApp = nil
    }

    // MARK: Panneaux.

    private func showOverlays() {
        overlays = NSScreen.screens.map { screen in
            let controller = OverlayController(screen: screen)
            controller.onRegion = { [weak self] rect in self?.commitRegion(rect, on: screen) }
            controller.onWindow = { [weak self] id in self?.commitWindow(id) }
            controller.onDisplay = { [weak self] in self?.commitDisplay(screen) }
            controller.onCancel = { [weak self] in self?.cancel() }
            controller.show(mode: appState.mode)
            return controller
        }
    }

    func refreshOverlayModes() {
        overlays.forEach { $0.show(mode: appState.mode) }
    }

    private func showBar() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }
        let host = NSHostingView(rootView: CaptureBarHostView(appState: appState, session: self))
        let fitting = host.fittingSize
        let width = max(fitting.width, 560)
        let height = max(fitting.height, 64)
        let frame = screen.visibleFrame
        let origin = restoredBarOrigin(
            defaultingTo: CGPoint(x: frame.midX - width / 2, y: frame.minY + 24),
            size: NSSize(width: width, height: height)
        )
        let panel = CaptureBarPanel(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)))
        panel.contentView = host
        barPanel = panel
        panel.orderFrontRegardless()
    }

    private func controllerForMouse() -> OverlayController? {
        let mouse = NSEvent.mouseLocation
        return overlays.first { $0.screen.frame.contains(mouse) }
    }

    // MARK: Validation.

    /// Bouton Capturer de la barre (utilise la sélection / le survol en cours).
    func commitFromBar() {
        guard isActive else { return }
        let target = controllerForMouse() ?? overlays.first
        switch appState.mode {
        case .region:
            if let rect = target?.selection, rect.width >= 4, rect.height >= 4, let controller = target {
                commitRegion(rect, on: controller.screen)
            } else {
                NSSound.beep()
            }
        case .window:
            if let id = target?.highlightedWindow {
                commitWindow(id)
            } else {
                NSSound.beep()
            }
        case .screen:
            if let screen = target?.screen {
                commitDisplay(screen)
            }
        case .video:
            if let rect = target?.selection, rect.width >= 4, rect.height >= 4, let controller = target {
                startRecording(rect: rect, on: controller.screen)
            } else if let screen = target?.screen {
                startRecording(rect: nil, on: screen)
            }
        case .scroll:
            if let rect = target?.selection, rect.width >= 50, rect.height >= 100, let controller = target {
                beginScrollCapture(rect: rect, on: controller.screen)
            } else {
                NSSound.beep()
            }
        }
    }

    private func commitRegion(_ rect: CGRect, on screen: NSScreen) {
        guard isActive else { return }
        if appState.mode == .video {
            startRecording(rect: rect, on: screen)
            return
        }
        if appState.mode == .scroll {
            beginScrollCapture(rect: rect, on: screen)
            return
        }
        // La zone peut déborder sur un autre écran : capturer sur celui du centre.
        let centerGlobal = CGPoint(x: screen.frame.minX + rect.midX, y: screen.frame.maxY - rect.midY)
        let display = NSScreen.screens.first { $0.frame.contains(centerGlobal) } ?? screen
        var local = CGRect(
            x: screen.frame.minX + rect.minX - display.frame.minX,
            y: display.frame.maxY - (screen.frame.maxY - rect.minY),
            width: rect.width,
            height: rect.height
        )
        local = local.intersection(CGRect(origin: .zero, size: display.frame.size))
        guard !local.isNull, local.width >= 1, local.height >= 1,
              let target = CaptureService.target(for: display) else {
            cancel()
            return
        }
        runCapture(.region(displayID: target.displayID, rect: local, scale: target.scale))
    }

    private func commitWindow(_ id: CGWindowID) {
        guard isActive else { return }
        runCapture(.window(id: id))
    }

    private func commitDisplay(_ screen: NSScreen) {
        guard isActive else { return }
        guard let target = CaptureService.target(for: screen) else {
            cancel()
            return
        }
        runCapture(.display(id: target.displayID, scale: target.scale))
    }

    private enum CaptureKind {
        case region(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat)
        case window(id: CGWindowID)
        case display(id: CGDirectDisplayID, scale: CGFloat)
    }

    private func runCapture(_ kind: CaptureKind) {
        let delay = appState.timer.rawValue
        // Avec minuteur, la barre reste visible pour afficher le décompte.
        overlays.forEach { $0.hide() }
        overlays.removeAll()
        if delay <= 0 {
            saveBarPosition()
            barPanel?.orderOut(nil)
            barPanel = nil
        }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                for remaining in stride(from: delay, to: 0, by: -1) {
                    countdown = remaining
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                countdown = nil
            }
            await performCapture(kind)
        }
    }

    private func performCapture(_ kind: CaptureKind) async {
        saveBarPosition()
        barPanel?.orderOut(nil)
        barPanel = nil
        countdown = nil
        do {
            let cgImage: CGImage
            switch kind {
            case .region(let displayID, let rect, let scale):
                cgImage = try await capture.captureRegion(displayID: displayID, rect: rect, scale: scale)
                lastCapture = LastCapture(displayID: displayID, rect: rect, scale: scale)
            case .window(let id):
                cgImage = try await captureWindowOrFallback(id: id)
            case .display(let id, let scale):
                cgImage = try await capture.captureDisplay(id: id, scale: scale)
            }
            finishCapture(image: cgImage)
        } catch {
            isActive = false
            reactivateFrontApp()
            showError(error)
        }
    }

    private func captureWindowOrFallback(id: CGWindowID) async throws -> CGImage {
        if let frame = WindowLookup.frame(of: id),
           let display = NSScreen.screens.first(where: { $0.frame.intersects(frame) }),
           let target = CaptureService.target(for: display) {
            let pixelSize = Geometry.pixelSize(points: frame.size, scale: target.scale)
            do {
                let image = try await capture.captureWindow(windowID: id, pixelSize: pixelSize)
                // Certaines fenêtres rendent une image vide : repli sur la zone.
                if image.width >= 2 && image.height >= 2 {
                    return image
                }
            } catch {}
                let local = CGRect(
                    x: frame.minX - display.frame.minX,
                    y: display.frame.maxY - frame.maxY,
                    width: frame.width,
                    height: frame.height
                ).intersection(CGRect(origin: .zero, size: display.frame.size))
                return try await capture.captureRegion(displayID: target.displayID, rect: local, scale: target.scale)
        }
        throw CaptureError.windowNotFound
    }

    private func finishCapture(image: CGImage) {
        let settings = appState.settings
        if settings.shutterSound {
            playShutter()
        }
        DestinationService.route(image: image, destination: appState.destination, settings: settings)
        let shot = CapturedShot(
            image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            name: settings.sampleFileName()
        )
        appState.history.add(shot)
        isActive = false
        reactivateFrontApp()
        showToast(shot: shot)
    }

    /// Répète la dernière zone (F4), sans rouvrir l'overlay.
    func repeatLast() {
        guard !isActive, !isRecording, let last = lastCapture else { return }
        guard CGPreflightScreenCaptureAccess() else { return }
        isActive = true
        frontApp = NSWorkspace.shared.frontmostApplication
        hideToast()
        runCapture(.region(displayID: last.displayID, rect: last.rect, scale: last.scale))
    }

    // MARK: Miniature réelle.

    private func showToast(shot: CapturedShot) {
        hideToast()
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 232, height: 176)
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width - 16,
            y: screen.visibleFrame.minY + 16
        )
        let panel = ToastPanel(contentRect: NSRect(origin: origin, size: size))
        let id = shot.id
        panel.contentView = NSHostingView(rootView: PreviewToastView(
            shot: shot,
            autoDismiss: appState.settings.toastDuration,
            onCopy: { [weak self] in MainActor.assumeIsolated { self?.copyToastShot(id) } },
            onSave: { [weak self] in MainActor.assumeIsolated { self?.saveToastShot(id) } },
            onAnnotate: { [weak self] in MainActor.assumeIsolated { self?.openEditor(for: id) } },
            onShare: { [weak self] in MainActor.assumeIsolated { self?.shareToastShot(id) } },
            onDelete: { [weak self] in MainActor.assumeIsolated { self?.deleteToastShot(id) } },
            onDismiss: { [weak self] in MainActor.assumeIsolated { self?.hideToast() } }
        ))
        toastPanel = panel
        panel.orderFrontRegardless()
    }

    private func hideToast() {
        toastPanel?.orderOut(nil)
        toastPanel = nil
    }

    private func toastImage(for id: CapturedShot.ID) -> CGImage? {
        guard let shot = appState.history.shots.first(where: { $0.id == id }) else { return nil }
        return Images.cgImage(from: shot.image)
    }

    private func copyToastShot(_ id: CapturedShot.ID) {
        guard let image = toastImage(for: id) else { return }
        DestinationService.copy(image)
    }

    private func saveToastShot(_ id: CapturedShot.ID) {
        guard let image = toastImage(for: id) else { return }
        DestinationService.save(image, settings: appState.settings)
    }

    private func shareToastShot(_ id: CapturedShot.ID) {
        guard let image = toastImage(for: id),
              let view = toastPanel?.contentView,
              let shot = appState.history.shots.first(where: { $0.id == id }) else { return }
        DestinationService.share(image, name: shot.name, from: view)
    }

    private func deleteToastShot(_ id: CapturedShot.ID) {
        appState.history.remove(id)
        hideToast()
    }

    // MARK: Édition.

    private func openEditor(for id: CapturedShot.ID) {
        guard let shot = appState.history.shots.first(where: { $0.id == id }) else { return }
        hideToast()
        editor.show(
            shot: shot,
            onDone: { [weak self] image in self?.finishEditing(id: id, image: image) },
            onCancel: {}
        )
    }

    private func finishEditing(id: CapturedShot.ID, image: NSImage) {
        appState.history.replaceImage(of: id, with: image)
        if let cgImage = Images.cgImage(from: image) {
            DestinationService.route(image: cgImage, destination: appState.destination, settings: appState.settings)
        }
        if let shot = appState.history.shots.first(where: { $0.id == id }) {
            showToast(shot: shot)
        }
    }

    // MARK: Enregistrement vidéo.

    private func startRecording(rect: CGRect?, on screen: NSScreen) {
        guard !isRecording, let target = CaptureService.target(for: screen) else { return }
        overlays.forEach { $0.hide() }
        overlays.removeAll()
        saveBarPosition()
        barPanel?.orderOut(nil)
        barPanel = nil
        let settings = appState.settings
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Focale-recording-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let pixelSize = Geometry.pixelSize(points: target.frame.size, scale: target.scale)
        recordingCrop = rect
        recordingScale = target.scale
        let fileName = settings.sampleVideoFileName()
        recordingFileName = fileName
        let capturesAudio = settings.recordSystemAudio
        Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.start(
                    displayID: target.displayID,
                    windowID: nil,
                    pixelSize: pixelSize,
                    capturesAudio: capturesAudio,
                    url: tempURL
                )
                isRecording = true
                showRecordingPanel(fileName: fileName)
            } catch {
                isActive = false
                reactivateFrontApp()
                showError(error)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        hideRecordingPanel()
        Task { [weak self] in
            guard let self else { return }
            let tempURL = await recorder.stop()
            guard let tempURL else {
                isActive = false
                reactivateFrontApp()
                return
            }
            do {
                let finalURL = try await finalizeRecording(tempURL: tempURL)
                finishRecording(url: finalURL)
            } catch {
                isActive = false
                reactivateFrontApp()
                showError(error)
            }
        }
    }

    private func finalizeRecording(tempURL: URL) async throws -> URL {
        let settings = appState.settings
        let folder = URL(fileURLWithPath: settings.saveFolderPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let croppedURL: URL
        if let crop = recordingCrop, crop.width >= 8, crop.height >= 8 {
            let intermediate = FileManager.default.temporaryDirectory
                .appendingPathComponent("Focale-cropped-\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            try await VideoService.transcodeCrop(input: tempURL, crop: crop, scale: recordingScale, output: intermediate)
            try? FileManager.default.removeItem(at: tempURL)
            croppedURL = intermediate
        } else {
            croppedURL = tempURL
        }
        // Nom figé au démarrage : identique au nom affiché dans le panneau,
        // même si les secondes ont changé pendant l'enregistrement.
        let baseName = recordingFileName.isEmpty ? settings.sampleVideoFileName() : recordingFileName
        guard let finalURL = DestinationService.uniqueURL(in: folder, baseName: baseName) else {
            throw VideoError.transcodeFailed
        }
        if settings.videoFormat == .gif {
            try await VideoService.convertToGIF(input: croppedURL, output: finalURL)
            try? FileManager.default.removeItem(at: croppedURL)
            return finalURL
        }
        if croppedURL != finalURL {
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: croppedURL, to: finalURL)
        }
        return finalURL
    }

    private func finishRecording(url: URL) {
        Task { [weak self] in
            guard let self else { return }
            let thumb = await VideoService.thumbnail(for: url)
            let duration = await VideoService.duration(of: url)
            let image = thumb.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
                ?? Images.samplePhoto(seed: 9, size: CGSize(width: 640, height: 400))
            let shot = CapturedShot(
                image: image,
                name: url.deletingPathExtension().lastPathComponent,
                kind: .video,
                fileURL: url,
                duration: duration
            )
            appState.history.add(shot)
            // La vidéo est toujours enregistrée ; le presse-papiers reçoit le fichier.
            if appState.destination == .clipboard || appState.destination == .both {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
            }
            isActive = false
            reactivateFrontApp()
            showVideoToast(shot: shot)
        }
    }

    private func showRecordingPanel(fileName: String) {
        hideRecordingPanel()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }
        let size = NSSize(width: 380, height: 56)
        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 16)
        let panel = FloatingStatusPanel(contentRect: NSRect(origin: origin, size: size))
        panel.contentView = NSHostingView(rootView: RecordingIndicatorView(
            startTime: Date(),
            fileName: fileName,
            onStop: { [weak self] in MainActor.assumeIsolated { self?.stopRecording() } }
        ))
        recordingPanel = panel
        panel.orderFrontRegardless()
    }

    private func hideRecordingPanel() {
        recordingPanel?.orderOut(nil)
        recordingPanel = nil
    }

    private func showVideoToast(shot: CapturedShot) {
        hideToast()
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 232, height: 176)
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width - 16,
            y: screen.visibleFrame.minY + 16
        )
        let panel = ToastPanel(contentRect: NSRect(origin: origin, size: size))
        let id = shot.id
        panel.contentView = NSHostingView(rootView: VideoToastView(
            shot: shot,
            autoDismiss: appState.settings.toastDuration,
            onPlay: { [weak self] in MainActor.assumeIsolated { self?.playToastVideo(id) } },
            onShare: { [weak self] in MainActor.assumeIsolated { self?.shareToastVideo(id) } },
            onReveal: { [weak self] in MainActor.assumeIsolated { self?.revealToastVideo(id) } },
            onDelete: { [weak self] in MainActor.assumeIsolated { self?.deleteToastVideo(id) } },
            onDismiss: { [weak self] in MainActor.assumeIsolated { self?.hideToast() } }
        ))
        toastPanel = panel
        panel.orderFrontRegardless()
    }

    private func videoURL(for id: CapturedShot.ID) -> URL? {
        appState.history.shots.first { $0.id == id }?.fileURL
    }

    private func playToastVideo(_ id: CapturedShot.ID) {
        guard let url = videoURL(for: id) else { return }
        NSWorkspace.shared.open(url)
    }

    private func shareToastVideo(_ id: CapturedShot.ID) {
        guard let url = videoURL(for: id), let view = toastPanel?.contentView else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    private func revealToastVideo(_ id: CapturedShot.ID) {
        guard let url = videoURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteToastVideo(_ id: CapturedShot.ID) {
        if let url = videoURL(for: id) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        appState.history.remove(id)
        hideToast()
    }

    // MARK: Capture défilante.

    private func beginScrollCapture(rect: CGRect, on screen: NSScreen) {
        guard !isRecording else { return }
        let centerGlobal = CGPoint(x: screen.frame.minX + rect.midX, y: screen.frame.maxY - rect.midY)
        let display = NSScreen.screens.first { $0.frame.contains(centerGlobal) } ?? screen
        guard let target = CaptureService.target(for: display) else {
            cancel()
            return
        }
        var local = CGRect(
            x: screen.frame.minX + rect.minX - display.frame.minX,
            y: display.frame.maxY - (screen.frame.maxY - rect.minY),
            width: rect.width,
            height: rect.height
        )
        local = local.intersection(CGRect(origin: .zero, size: display.frame.size))
        guard !local.isNull, local.width >= 50, local.height >= 100 else {
            cancel()
            return
        }
        overlays.forEach { $0.hide() }
        overlays.removeAll()
        saveBarPosition()
        barPanel?.orderOut(nil)
        barPanel = nil
        showScrollPanel()
        scrollTask?.cancel()
        scrollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await scroller.run(displayID: target.displayID, rect: local, scale: target.scale)
                hideScrollPanel()
                finishCapture(image: image)
            } catch is CancellationError {
                hideScrollPanel()
                teardown()
            } catch {
                hideScrollPanel()
                isActive = false
                reactivateFrontApp()
                if (error as? ScrollError) == .accessibilityDenied {
                    openAccessibilitySettings()
                }
                showError(error)
            }
        }
    }

    private func showScrollPanel() {
        hideScrollPanel()
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 340, height: 56)
        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 16)
        let panel = FloatingStatusPanel(contentRect: NSRect(origin: origin, size: size))
        panel.contentView = NSHostingView(rootView: ScrollProgressView(
            startTime: Date(),
            onCancel: { [weak self] in MainActor.assumeIsolated { self?.cancelScroll() } }
        ))
        scrollPanel = panel
        panel.orderFrontRegardless()
    }

    private func hideScrollPanel() {
        scrollPanel?.orderOut(nil)
        scrollPanel = nil
    }

    private func cancelScroll() {
        scrollTask?.cancel()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Position de la barre + son.

    private func saveBarPosition() {
        if let panel = barPanel {
            appState.settings.saveBarPosition(panel.frame.origin)
        }
    }

    private func restoredBarOrigin(defaultingTo origin: CGPoint, size: NSSize) -> CGPoint {
        guard let x = appState.settings.barPositionX,
              let y = appState.settings.barPositionY else { return origin }
        let candidate = CGPoint(x: x, y: y)
        let rect = CGRect(origin: candidate, size: size)
        for screen in NSScreen.screens where screen.visibleFrame.intersects(rect) {
            return candidate
        }
        return origin
    }

    private func playShutter() {
        guard let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true) else {
            return
        }
        sound.volume = 0.6
        sound.play()
    }

    // MARK: Divers.

    func openSettings() {
        // Ferme la session (hors enregistrement) : l'overlay plein écran
        // intercepterait tous les clics de la fenêtre Réglages, restée dessous.
        if isActive, !isRecording { cancel() }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "La capture a échoué"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
