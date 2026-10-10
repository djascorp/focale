import AppKit
import SwiftUI

// MARK: - Fenêtre d'onboarding (première ouverture + permission refusée).

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinishRef: (@MainActor () -> Void)?

    func show(settings: AppSettings, startPage: Int, onFinish: @escaping @MainActor () -> Void) {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        onFinishRef = onFinish
        let view = OnboardingView(
            settings: settings,
            startPage: startPage,
            onFinish: { MainActor.assumeIsolated { [weak self] in self?.requestClose() } }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Bienvenue dans Focale"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 648, height: 540))
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestClose() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let callback = onFinishRef
        onFinishRef = nil
        window = nil
        callback?()
    }
}
