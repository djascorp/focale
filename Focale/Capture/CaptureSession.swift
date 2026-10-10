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
        if !hasOnboarded {
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
        guard !isActive else { return }
        guard CGPreflightScreenCaptureAccess() else {
            onboarding.show(settings: appState.settings, startPage: 1) { [weak self] in
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
        let mouse = NSEvent.mouseLocation
        let keyPanel = overlays.first { $0.screen.frame.contains(mouse) }?.panel ?? overlays.first?.panel
        keyPanel?.makeKeyAndOrderFront(nil)
    }

    func cancel() {
        guard isActive else { return }
        teardown()
    }

    private func teardown() {
        captureTask?.cancel()
        captureTask = nil
        countdown = nil
        overlays.forEach { $0.hide() }
        overlays.removeAll()
        barPanel?.orderOut(nil)
        barPanel = nil
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
        let origin = CGPoint(x: frame.midX - width / 2, y: frame.minY + 24)
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
            NSSound.beep()
        }
    }

    private func commitRegion(_ rect: CGRect, on screen: NSScreen) {
        guard isActive else { return }
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
        runCapture(.display(id: target.displayID, size: target.frame.size, scale: target.scale))
    }

    private enum CaptureKind {
        case region(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat)
        case window(id: CGWindowID)
        case display(id: CGDirectDisplayID, size: CGSize, scale: CGFloat)
    }

    private func runCapture(_ kind: CaptureKind) {
        let delay = appState.timer.rawValue
        // Avec minuteur, la barre reste visible pour afficher le décompte.
        overlays.forEach { $0.hide() }
        overlays.removeAll()
        if delay <= 0 {
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
            case .display(let id, let size, let scale):
                cgImage = try await capture.captureDisplay(id: id, size: size, scale: scale)
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
                return try await capture.captureWindow(windowID: id, pixelSize: pixelSize)
            } catch {
                let local = CGRect(
                    x: frame.minX - display.frame.minX,
                    y: display.frame.maxY - frame.maxY,
                    width: frame.width,
                    height: frame.height
                ).intersection(CGRect(origin: .zero, size: display.frame.size))
                return try await capture.captureRegion(displayID: target.displayID, rect: local, scale: target.scale)
            }
        }
        throw CaptureError.windowNotFound
    }

    private func finishCapture(image: CGImage) {
        let settings = appState.settings
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
        guard !isActive, let last = lastCapture else { return }
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

    // MARK: Divers.

    func openSettings() {
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
