import SwiftUI

// MARK: - Barre flottante de capture (§7.2.A : capsule 560×56, tout est visible).

struct CaptureBarView: View {
    @Binding var mode: CaptureMode
    @Binding var destination: Destination
    @Binding var timer: CaptureTimerOption
    var canRepeatLast: Bool = false
    var onCapture: () -> Void = {}
    var onRepeatLast: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onCancel: () -> Void = {}
    /// Décompte du minuteur affiché dans la barre (nil hors décompte).
    var countdown: Int? = nil

    @Namespace private var modeIndicator
    @State private var hoveredMode: CaptureMode?
    @State private var hoveredDestination: Destination?

    var body: some View {
        HStack(spacing: 4) {
            modeGroup
            Divider().padding(.vertical, 12)
            destinationGroup
            Divider().padding(.vertical, 12)
            timerMenu
            repeatButton
            Divider().padding(.vertical, 12)
            captureButton
            settingsButton
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .focaleBarBackground()
        .focalePanelShadow()
        .focaleTopHighlight()
        .onKeyPress(phases: .down, action: handleKey)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Barre de capture Focale")
    }

    // MARK: Modes (F2) avec indicateur coulissant.

    private var modeGroup: some View {
        HStack(spacing: 2) {
            ForEach(CaptureMode.allCases) { item in
                Button {
                    withAnimation(.focaleModeSwitch) { mode = item }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(mode == item ? .white : .primary)
                        .frame(width: 38, height: 36)
                        .background {
                            if mode == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.focaleAccentStart)
                                    .matchedGeometryEffect(id: "mode-indicator", in: modeIndicator)
                            } else if hoveredMode == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.secondary.opacity(0.12))
                            }
                        }
                }
                .buttonStyle(FocalePressableStyle())
                .onHover { hoveredMode = $0 ? item : nil }
                .help("\(item.title) (\(item.keyHint))")
                .accessibilityLabel(item.title)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode de capture")
    }

    // MARK: Destination visible (F3), jamais dans un sous-menu.

    private var destinationGroup: some View {
        HStack(spacing: 2) {
            ForEach(Destination.allCases) { item in
                Button {
                    withAnimation(.focaleModeSwitch) { destination = item }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(destination == item ? Color.focaleAccentStart : .secondary)
                        .frame(width: 32, height: 36)
                        .background {
                            if destination == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.focaleAccentStart.opacity(0.14))
                            } else if hoveredDestination == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.secondary.opacity(0.12))
                            }
                        }
                }
                .buttonStyle(FocalePressableStyle())
                .onHover { hoveredDestination = $0 ? item : nil }
                .help("\(item.title)")
                .accessibilityLabel("Destination : \(item.title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Destination")
    }

    // MARK: Minuteur (F7) + répétition (F4).

    private var timerMenu: some View {
        Menu {
            ForEach(CaptureTimerOption.allCases) { option in
                Button {
                    timer = option
                } label: {
                    if timer == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                if let countdown {
                    Text("\(countdown)")
                        .font(.focaleBadge)
                        .foregroundStyle(Color.focaleDanger)
                } else if let short = timer.shortLabel {
                    Text(short)
                        .font(.focaleCaption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(timer == .off ? .secondary : Color.focaleAccentStart)
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Minuteur (T)")
        .accessibilityLabel("Minuteur : \(timer.title)")
    }

    private var repeatButton: some View {
        BarIconButton(
            icon: "repeat",
            size: 36,
            help: "Répéter la dernière zone (R)",
            action: onRepeatLast
        )
        .disabled(!canRepeatLast)
        .opacity(canRepeatLast ? 1 : 0.4)
    }

    // MARK: Actions.

    private var captureButton: some View {
        Button(action: onCapture) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Capturer")
            }
        }
        .buttonStyle(FocaleAccentButtonStyle())
        .keyboardShortcut(.defaultAction)
        .help("Capturer (Entrée)")
    }

    private var settingsButton: some View {
        BarIconButton(icon: "gearshape", size: 36, help: "Réglages (⌘,)") {
            onOpenSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }

    // MARK: Clavier d'abord (§7.1 : chaque action a un raccourci affiché).

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            onCancel()
            return .handled
        }
        switch press.key.character {
        case "1": mode = .region
        case "2": mode = .window
        case "3": mode = .screen
        case "4": mode = .video
        case "5": mode = .scroll
        case "t": timer = timer.next()
        case "r": if canRepeatLast { onRepeatLast() } else { return .ignored }
        case "c": onCapture()
        default: return .ignored
        }
        return .handled
    }
}

#Preview("Barre flottante") {
    @Previewable @State var mode: CaptureMode = .region
    @Previewable @State var destination: Destination = .clipboard
    @Previewable @State var timer: CaptureTimerOption = .off
    CaptureBarView(
        mode: $mode,
        destination: $destination,
        timer: $timer,
        canRepeatLast: true
    )
    .padding(40)
    .background(FocaleImageView(image: Images.sampleDesktop(size: CGSize(width: 900, height: 300))))
}
