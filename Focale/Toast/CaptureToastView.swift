import SwiftUI

// MARK: - Miniature flottante du résultat (unifiée image + vidéo).
//
// Un clic ouvre la fenêtre d'aperçu ; le survol révèle les actions ;
// un balayage vers la droite écarte. L'auto-dismiss s'interrompt
// pendant le survol : le temps de décider.

struct CaptureToastView: View {
    let shot: CapturedShot
    var autoDismiss: TimeInterval = 0
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onAnnotate: () -> Void = {}
    var onShare: () -> Void = {}
    var onReveal: () -> Void = {}
    var onDelete: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var isHovering = false
    @State private var appeared = false
    @State private var dragOffset: CGSize = .zero

    private var isVideo: Bool { shot.kind == .video }
    private var hasFile: Bool { shot.fileURL != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            thumbnail
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .help("Cliquer pour ouvrir l'aperçu")
            if isHovering {
                actionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 10)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .offset(dragOffset)
        .onAppear {
            withAnimation(.focaleToast) { appeared = true }
        }
        .onHover { hovering in
            withAnimation(.focaleStandard) { isHovering = hovering }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width > 0 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.width > 80 {
                        withAnimation(.focaleToast) { appeared = false }
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = .zero }
                    }
                }
        )
        .task { await autoDismissWhenIdle() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aperçu : \(shot.name)")
    }

    // MARK: Vignette : image, ou affiche vidéo + durée.

    private var thumbnail: some View {
        ZStack {
            FocaleImageView(image: shot.image)
                .frame(width: 208, height: 136)
            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
        .frame(width: 208, height: 136)
        .overlay(alignment: .bottomTrailing) {
            if isVideo {
                Text(Self.durationText(shot.duration))
                    .font(.focaleBadge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(8)
            }
        }
    }

    // MARK: Actions au survol.

    private var actionBar: some View {
        HStack(spacing: 2) {
            if isVideo {
                toastButton(icon: "play.fill", help: "Ouvrir l'aperçu et lire", action: onOpen)
            } else {
                toastButton(icon: "doc.on.doc", help: "Copier dans le presse-papiers", action: onCopy)
                toastButton(icon: "square.and.arrow.down", help: "Enregistrer dans le dossier par défaut", action: onSave)
                toastButton(icon: "pencil.tip", help: "Annoter dans l'éditeur", action: onAnnotate)
            }
            toastButton(icon: "square.and.arrow.up", help: "Partager", action: onShare)
            if hasFile {
                toastButton(icon: "folder", help: "Révéler dans le Finder", action: onReveal)
            }
            toastButton(icon: "trash", help: "Supprimer la capture et son fichier", action: onDelete, danger: true)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
    }

    private func toastButton(icon: String, help: String, action: @escaping () -> Void, danger: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(danger ? Color.focaleDanger : .primary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Disparition automatique, suspendue pendant le survol.

    private func autoDismissWhenIdle() async {
        guard autoDismiss > 0 else { return }
        var remaining = autoDismiss
        while remaining > 0 {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            if !isHovering {
                remaining -= 0.25
            }
        }
        withAnimation(.focaleToast) { appeared = false }
        onDismiss()
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
