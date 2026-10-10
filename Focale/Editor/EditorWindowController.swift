import AppKit
import SwiftUI

// MARK: - Fenêtre d'édition réelle (la croix rouge annule comme le bouton).

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var didFinish = false
    private var onDoneRef: (@MainActor (NSImage) -> Void)?
    private var onCancelRef: (@MainActor () -> Void)?

    func show(
        shot: CapturedShot,
        onDone: @escaping @MainActor (NSImage) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        close()
        didFinish = false
        onDoneRef = onDone
        onCancelRef = onCancel
        let view = EditorView(
            shot: shot,
            onDone: { image in MainActor.assumeIsolated { [weak self] in self?.finish(image: image) } },
            onCancel: { MainActor.assumeIsolated { [weak self] in self?.requestClose() } }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Annoter — \(shot.name)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private func finish(image: NSImage) {
        didFinish = true
        let callback = onDoneRef
        onDoneRef = nil
        onCancelRef = nil
        window?.close()
        window = nil
        callback?(image)
    }

    private func requestClose() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Croix rouge ou bouton Annuler : un seul chemin d'annulation.
        guard !didFinish else {
            window = nil
            return
        }
        didFinish = true
        let callback = onCancelRef
        onDoneRef = nil
        onCancelRef = nil
        window = nil
        callback?()
    }
}
