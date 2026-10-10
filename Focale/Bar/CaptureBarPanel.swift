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
            selection: Binding(
                get: { appState.selection },
                set: { appState.setSelection($0) }
            ),
            kind: Binding(
                get: { appState.kind },
                set: { appState.setKind($0) }
            ),
            destination: $appState.destination,
            timer: $appState.timer,
            folderName: session.folderDisplayName,
            canRepeatLast: session.canRepeatLast,
            onCapture: { session.commitFromBar() },
            onRepeatLast: { session.repeatLast() },
            onOpenSettings: { session.openSettings() },
            onCancel: { session.cancel() },
            onChooseFolder: { session.chooseFolder($0) },
            countdown: session.countdown
        )
        .onChange(of: appState.selection) { _, _ in
            session.refreshOverlayModes()
        }
    }
}
