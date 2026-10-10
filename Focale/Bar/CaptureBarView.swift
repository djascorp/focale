import SwiftUI

// MARK: - Barre flottante de capture.
//
// Trois décisions indépendantes, de gauche à droite :
// 1. Ce que la souris choisit à l'écran (zone, fenêtre, écran, défilement).
// 2. Le type de capture (photo ou vidéo).
// 3. La destination (presse-papiers et/ou dossier, dossier choisiable).

struct CaptureBarView: View {
    @Binding var selection: SelectionMode
    @Binding var kind: CaptureKind
    @Binding var destination: Destination
    @Binding var timer: CaptureTimerOption
    var folderName: String = "Bureau"
    var canRepeatLast: Bool = false
    var onCapture: () -> Void = {}
    var onRepeatLast: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onCancel: () -> Void = {}
    var onChooseFolder: (QuickFolder) -> Void = { _ in }
    /// Décompte du minuteur affiché dans la barre (nil hors décompte).
    var countdown: Int? = nil

    @Namespace private var selectionIndicator
    @Namespace private var kindIndicator
    @State private var hoveredSelection: SelectionMode?
    @State private var hoveredDestination: Destination?

    var body: some View {
        HStack(spacing: 4) {
            selectionGroup
            Divider().padding(.vertical, 12)
            kindGroup
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

    // MARK: 1. Type de sélection, avec indicateur coulissant.

    private var selectionGroup: some View {
        HStack(spacing: 2) {
            ForEach(SelectionMode.allCases) { item in
                Button {
                    applySelection(item)
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selection == item ? .white : .primary)
                        .frame(width: 38, height: 36)
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.focaleAccentStart)
                                    .matchedGeometryEffect(id: "selection-indicator", in: selectionIndicator)
                            } else if hoveredSelection == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.secondary.opacity(0.12))
                            }
                        }
                }
                .buttonStyle(FocalePressableStyle())
                .onHover { hoveredSelection = $0 ? item : nil }
                .disabled(!item.supportsVideo && kind == .video)
                .opacity(!item.supportsVideo && kind == .video ? 0.35 : 1)
                .help("\(item.title) — \(item.hint) (\(item.keyHint))")
                .accessibilityLabel("\(item.title) : \(item.hint)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type de sélection")
    }

    // MARK: 2. Type de capture : photo ou vidéo.

    private var kindGroup: some View {
        HStack(spacing: 2) {
            ForEach(CaptureKind.allCases) { item in
                Button {
                    applyKind(item)
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(kind == item ? .white : .primary)
                        .frame(width: 38, height: 36)
                        .background {
                            if kind == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.focaleAccentStart)
                                    .matchedGeometryEffect(id: "kind-indicator", in: kindIndicator)
                            }
                        }
                }
                .buttonStyle(FocalePressableStyle())
                .help("\(item.title) — \(item.hint) (\(item.keyHint))")
                .accessibilityLabel("\(item.title) : \(item.hint)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type de capture")
    }

    // MARK: 3. Destination : presse-papiers et/ou dossier.

    private var destinationGroup: some View {
        HStack(spacing: 2) {
            destinationButton(.clipboard)
            destinationButton(.both)
            folderMenu
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Destination")
    }

    private func destinationButton(_ item: Destination) -> some View {
        Button {
            destination = item
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive(item) ? Color.focaleAccentStart : .secondary)
                .frame(width: 32, height: 36)
                .background {
                    if isActive(item) {
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
        .help("\(item.title) — \(item.hint)")
        .accessibilityLabel("Destination : \(item.title), \(item.hint)")
    }

    /// Presse-papiers et dossier peuvent être combinés : chaque bouton
    /// s'allume dès que la destination l'inclut.
    private func isActive(_ item: Destination) -> Bool {
        switch item {
        case .clipboard: destination == .clipboard || destination == .both
        case .file: destination == .file || destination == .both
        case .both: destination == .both
        }
    }

    /// Bouton dossier : ouvre le choix rapide (Bureau, Documents, autre…).
    private var folderMenu: some View {
        Menu {
            folderRow(title: "Bureau", choice: .desktop)
            folderRow(title: "Documents", choice: .documents)
            Divider()
            Button {
                onChooseFolder(.other)
            } label: {
                Label("Autre dossier…", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(folderName)
                    .font(.focaleCaption)
                    .lineLimit(1)
            }
            .foregroundStyle(isActive(.file) ? Color.focaleAccentStart : .secondary)
            .frame(maxWidth: 120, minHeight: 36)
            .background {
                if isActive(.file) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.focaleAccentStart.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Dossier — enregistre les captures dans « \(folderName) » ; Bureau, Documents ou un autre dossier au choix")
        .accessibilityLabel("Dossier : \(folderName)")
    }

    private func folderRow(title: String, choice: QuickFolder) -> some View {
        Button {
            onChooseFolder(choice)
        } label: {
            if folderName == title {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
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
                        .lineLimit(1)
                }
            }
            .foregroundStyle(timer == .off ? .secondary : Color.focaleAccentStart)
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Minuteur — délai avant capture (T)")
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
                Image(systemName: kind == .video ? "video.fill" : "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(kind == .video ? "Enregistrer" : "Capturer")
                    .lineLimit(1)
            }
            // Largeur idéale mesurée sans repli : le libellé ne coupe jamais
            // en deux lignes, la barre s'élargit à la place.
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(FocaleAccentButtonStyle())
        .keyboardShortcut(.defaultAction)
        .help(kind == .video ? "Démarrer l'enregistrement (Entrée)" : "Capturer (Entrée)")
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
        case "1": applySelection(.region)
        case "2": applySelection(.window)
        case "3": applySelection(.screen)
        case "4": applySelection(.scroll)
        case "p": applyKind(.photo)
        case "v": applyKind(.video)
        case "d": cycleDestination()
        case "t": timer = timer.next()
        case "r": if canRepeatLast { onRepeatLast() } else { return .ignored }
        case "c": onCapture()
        default: return .ignored
        }
        return .handled
    }

    /// Les combinaisons invalides se rabattent proprement (vidéo ↔ fenêtre…).
    private func applySelection(_ item: SelectionMode) {
        withAnimation(.focaleModeSwitch) { selection = item }
        if kind == .video, !item.supportsVideo {
            kind = .photo
        }
    }

    private func applyKind(_ item: CaptureKind) {
        withAnimation(.focaleModeSwitch) { kind = item }
        if item == .video, !selection.supportsVideo {
            selection = .region
        }
    }

    private func cycleDestination() {
        let all = Destination.allCases
        let index = all.firstIndex(of: destination) ?? 0
        destination = all[(index + 1) % all.count]
    }
}

#Preview("Barre flottante") {
    @Previewable @State var selection: SelectionMode = .region
    @Previewable @State var kind: CaptureKind = .photo
    @Previewable @State var destination: Destination = .clipboard
    @Previewable @State var timer: CaptureTimerOption = .off
    CaptureBarView(
        selection: $selection,
        kind: $kind,
        destination: $destination,
        timer: $timer,
        folderName: "Bureau",
        canRepeatLast: true
    )
    .padding(40)
    .background(FocaleImageView(image: Images.sampleDesktop(size: CGSize(width: 1100, height: 300))))
}
