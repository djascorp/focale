import AVKit
import AppKit
import SwiftUI

// MARK: - Actions proposées par la fenêtre d'aperçu du résultat.

struct PreviewActions {
    var onAnnotate: (() -> Void)?
    var onSaveAs: () -> Void = {}
    var onCopy: () -> Void = {}
    var onShare: () -> Void = {}
    var onReveal: (() -> Void)?
    var onDelete: () -> Void = {}
    var onClose: () -> Void = {}
}

// MARK: - Fenêtre d'aperçu : le résultat en grand, la décision ensuite.
//
// Ouverte par un clic sur la miniature ou un double-clic dans l'historique.
// L'utilisateur y voit la capture en taille réelle (ou la vidéo en lecture)
// et décide : annoter, enregistrer ailleurs, copier, partager, supprimer.

@MainActor
final class PreviewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// Ancre pour les popovers de partage.
    var contentView: NSView? { window?.contentView }

    func show(shot: CapturedShot, actions: PreviewActions) {
        if window != nil {
            window?.close()
        }
        let hosting = NSHostingController(rootView: PreviewView(shot: shot, actions: actions))
        // Sans cela, le contrôleur redimensionne la fenêtre d'après la taille
        // intrinsèque de NSImageView (l'image en pixels) : une capture plein
        // écran ouvrait une fenêtre plus grande que l'écran, ne laissant voir
        // qu'une tranche d'image sans la barre d'actions.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Aperçu — \(shot.name)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.setContentSize(Self.windowSize(for: shot))
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    /// Taille ajustée au contenu, raisonnable pour un écran portable.
    private static func windowSize(for shot: CapturedShot) -> NSSize {
        guard shot.kind == .image else {
            return NSSize(width: 840, height: 580)
        }
        let width = min(max(shot.pixelSize.width + 120, 640), 1180)
        let height = min(max(shot.pixelSize.height + 150, 460), 800)
        return NSSize(width: width, height: height)
    }
}

// MARK: - Contenu de l'aperçu.

struct PreviewView: View {
    let shot: CapturedShot
    let actions: PreviewActions

    @State private var player: AVPlayer?

    private var isVideo: Bool { shot.kind == .video }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color.focaleBackground)
        .onAppear {
            if isVideo, let url = shot.fileURL {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: Barre d'actions : décider après avoir vu.

    private var topBar: some View {
        HStack {
            Button("Fermer", action: actions.onClose)
                .keyboardShortcut(.cancelAction)
            Button("Supprimer", role: .destructive, action: actions.onDelete)
                .keyboardShortcut(.delete, modifiers: .command)
            Spacer()
            VStack(spacing: 1) {
                Text(shot.name)
                    .font(.focaleHeadline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 10) {
                if let onReveal = actions.onReveal {
                    Button("Révéler", action: onReveal)
                }
                Button("Copier", action: actions.onCopy)
                    .keyboardShortcut("c", modifiers: .command)
                Button("Partager", action: actions.onShare)
                Button("Enregistrer sous…", action: actions.onSaveAs)
                    .keyboardShortcut("s", modifiers: .command)
                if let onAnnotate = actions.onAnnotate {
                    Button("Annoter", action: onAnnotate)
                        .buttonStyle(FocaleAccentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: Contenu : image ajustée ou lecture vidéo.

    private var content: some View {
        Group {
            if isVideo {
                if let player {
                    PlayerView(player: player)
                } else {
                    ContentUnavailableView(
                        "Vidéo indisponible",
                        systemImage: "video.slash",
                        description: Text("Le fichier n'est plus à son emplacement d'origine.")
                    )
                }
            } else {
                GeometryReader { proxy in
                    let mapping = Geometry.aspectFit(content: shot.image.size, in: proxy.size)
                    FocaleImageView(image: shot.image)
                        .frame(width: mapping.fitted.width, height: mapping.fitted.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08))
    }

    private var subtitle: String {
        if isVideo {
            return "Vidéo · \(Self.durationText(shot.duration))"
        }
        return "\(Int(shot.pixelSize.width)) × \(Int(shot.pixelSize.height)) px"
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Lecteur AppKit.
//
// SwiftUI `VideoPlayer` (shim _AVKit_SwiftUI) plante à l'initialisation de
// ses métadonnées Swift sur cette configuration (SIGABRT au premier
// instantiement) : on passe par AVPlayerView d'AVKit, éprouvé.

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
