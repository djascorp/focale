import SwiftUI

// MARK: - Miniature flottante (§7.2.C : actions au survol, disparition réglable, balayage).

struct PreviewToastView: View {
    let shot: CapturedShot
    var autoDismiss: TimeInterval = 0
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onAnnotate: () -> Void = {}
    var onShare: () -> Void = {}
    var onDelete: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var isHovering = false
    @State private var appeared = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottom) {
            FocaleImageView(image: shot.image)
                .frame(width: 208, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
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
        .task {
            guard autoDismiss > 0 else { return }
            try? await Task.sleep(for: .seconds(autoDismiss))
            guard !Task.isCancelled else { return }
            withAnimation(.focaleToast) { appeared = false }
            onDismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aperçu : \(shot.name)")
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            toastButton(icon: "doc.on.doc", help: "Copier (⌘C)", action: onCopy)
            toastButton(icon: "square.and.arrow.down", help: "Enregistrer (⌘S)", action: onSave)
            toastButton(icon: "pencil.tip", help: "Annoter (A)", action: onAnnotate)
            toastButton(icon: "square.and.arrow.up", help: "Partager", action: onShare)
            toastButton(icon: "trash", help: "Supprimer (⌫)", action: onDelete, danger: true)
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
}

#Preview("Miniature flottante") {
    let shots = CapturedShot.mockSet()
    PreviewToastView(shot: shots[0])
        .padding(60)
        .background(FocaleImageView(image: Images.sampleDesktop(size: CGSize(width: 700, height: 400))))
}
