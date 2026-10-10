import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Fenêtre d'onboarding (première ouverture + permission refusée).

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinishRef: (@MainActor () -> Void)?
    private var grantTimer: Timer?

    /// - Parameter dismissWhenGranted: en mode récupération, referme la fenêtre
    ///   dès que macOS accorde l'accès, sans attendre un clic.
    func show(
        settings: AppSettings,
        startPage: Int,
        dismissWhenGranted: Bool = false,
        onFinish: @escaping @MainActor () -> Void
    ) {
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
        // Taille de fenêtre dictée ici uniquement (voir PreviewWindow).
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Bienvenue dans Focale"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 648, height: 540))
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if dismissWhenGranted {
            watchGrant()
        }
    }

    /// L'octroi prend effet au retour dans l'app (voire à sa réouverture) :
    /// scrute l'état TCC et referme dès l'accord pour ne jamais réafficher
    /// une demande déjà satisfaite.
    private func watchGrant() {
        stopWatchingGrant()
        grantTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.window != nil else { return }
                if CGPreflightScreenCaptureAccess() {
                    self.requestClose()
                }
            }
        }
    }

    private func stopWatchingGrant() {
        grantTimer?.invalidate()
        grantTimer = nil
    }

    private func requestClose() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        stopWatchingGrant()
        let callback = onFinishRef
        onFinishRef = nil
        window = nil
        callback?()
    }
}

// MARK: - Réouverture de l'app (macOS n'active l'autorisation qu'au relancement).

enum RelaunchHelper {
    static func relaunch() {
        let path = Bundle.main.bundleURL.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
