import AppKit
import SwiftUI

// MARK: - Panneau de la barre flottante (déplaçable par son fond).

final class CaptureBarPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // Au-dessus de l'overlay (.screenSaver) : la barre doit rester visible
        // et cliquable pendant la sélection.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Hôte SwiftUI de la barre (état partagé + session).

struct CaptureBarHostView: View {
    @Bindable var appState: AppState
    @Bindable var session: CaptureSession

    var body: some View {
        CaptureBarView(
            mode: $appState.mode,
            destination: $appState.destination,
            timer: $appState.timer,
            canRepeatLast: session.canRepeatLast,
            onCapture: { session.commitFromBar() },
            onRepeatLast: { session.repeatLast() },
            onOpenSettings: { session.openSettings() },
            onCancel: { session.cancel() },
            countdown: session.countdown
        )
        .onChange(of: appState.mode) { _, _ in
            session.refreshOverlayModes()
        }
    }
}
