import AppKit
import SwiftUI

// MARK: - Matériaux (§8.2 : verre dépoli, Liquid Glass sur macOS 26+).

extension View {
    @ViewBuilder
    func focaleBarBackground(cornerRadius: CGFloat = 28) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Liseré blanc à 12 % : reflet fin en haut des panneaux.
    func focaleTopHighlight(cornerRadius: CGFloat = 28) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Ombre large et douce, jamais de contour dur.
    func focalePanelShadow() -> some View {
        shadow(color: .black.opacity(0.25), radius: 32, x: 0, y: 12)
    }
}

// MARK: - Bouton principal (seul accent par écran).

struct FocaleAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.focaleLabel)
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(LinearGradient.focaleAccent, in: Capsule())
            .shadow(color: .focaleAccentStart.opacity(0.4), radius: configuration.isPressed ? 4 : 10, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.focaleStandard, value: configuration.isPressed)
    }
}

// MARK: - Style pressé : micro-interaction discrète (échelle + fondu).

struct FocalePressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.focaleStandard, value: configuration.isPressed)
    }
}

// MARK: - Bouton d'icône de barre.

struct BarIconButton: View {
    let icon: String
    var active: Bool = false
    var size: CGFloat = 36
    var help: String = ""
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(active ? .white : .primary)
                .frame(width: size, height: size)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.focaleAccentStart)
                    } else if hover {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.secondary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(FocalePressableStyle())
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Pastille de raccourci clavier.

struct KBDBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.focaleCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Pastille de dimensions (chiffres tabulaires, SF Mono).

struct DimensionBadge: View {
    let size: CGSize

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded()))")
            if let ratio = Geometry.simplifiedRatio(size), size.width >= 8, size.height >= 8 {
                Text(ratio).foregroundStyle(.secondary)
            }
        }
        .font(.focaleBadge)
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.72), in: Capsule())
    }
}

// MARK: - Affichage NSImage redimensionné (robuste, sans Image redimensionnée).

struct FocaleImageView: NSViewRepresentable {
    var image: NSImage?

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
    }
}
