import SwiftUI

// MARK: - Miniature vidéo : lecture, partage, révéler, supprimer.

struct VideoToastView: View {
    let shot: CapturedShot
    var autoDismiss: TimeInterval = 0
    var onPlay: () -> Void = {}
    var onShare: () -> Void = {}
    var onReveal: () -> Void = {}
    var onDelete: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var isHovering = false
    @State private var appeared = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                FocaleImageView(image: shot.image)
                    .frame(width: 208, height: 136)
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: Circle())
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatted(shot.duration))
                            .font(.focaleBadge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(8)
                    }
                }
            }
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
        .accessibilityLabel("Aperçu vidéo : \(shot.name)")
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            toastButton(icon: "play.fill", help: "Lire", action: onPlay)
            toastButton(icon: "square.and.arrow.up", help: "Partager", action: onShare)
            toastButton(icon: "folder", help: "Révéler dans le Finder", action: onReveal)
            toastButton(icon: "trash", help: "Supprimer", action: onDelete, danger: true)
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

    private func formatted(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
