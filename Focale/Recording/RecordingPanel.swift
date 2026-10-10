import AppKit
import SwiftUI

// MARK: - Panneau d'état flottant (enregistrement, progression défilante).

final class FloatingStatusPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - Indicateur d'enregistrement (durée + arrêt).

struct RecordingIndicatorView: View {
    let startTime: Date
    let fileName: String
    var onStop: () -> Void

    @State private var elapsed = 0
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.focaleDanger)
                .frame(width: 10, height: 10)
            Text(formatted(elapsed))
                .font(.focaleBadge)
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(fileName)
                .font(.focaleCaption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.focaleDanger, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Arrêter l'enregistrement")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .focaleBarBackground(cornerRadius: 22)
        .focalePanelShadow()
        .onReceive(ticker) { _ in
            elapsed = max(Int(Date().timeIntervalSince(startTime)), 0)
        }
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Progression de la capture défilante.

struct ScrollProgressView: View {
    let startTime: Date
    var onCancel: () -> Void

    @State private var elapsed = 0
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Capture défilante… \(formatted(elapsed))")
                .font(.focaleLabel)
                .foregroundStyle(.white)
                .monospacedDigit()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Annuler la capture défilante")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .focaleBarBackground(cornerRadius: 22)
        .focalePanelShadow()
        .onReceive(ticker) { _ in
            elapsed = max(Int(Date().timeIntervalSince(startTime)), 0)
        }
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
