import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Onglets des réglages (sélection explicite : chaque onglet est cliquable).

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, shortcuts, destination, presets, appearance, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "Général")
        case .shortcuts: String(localized: "Raccourcis")
        case .destination: String(localized: "Destination")
        case .presets: String(localized: "Préréglages")
        case .appearance: String(localized: "Apparence")
        case .privacy: String(localized: "Confidentialité")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .destination: "folder"
        case .presets: "square.stack"
        case .appearance: "paintbrush"
        case .privacy: "lock.shield"
        }
    }
}

// MARK: - Réglages (§7.2.F : 6 onglets, aperçu en direct).

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var onClearHistory: (() -> Void)?
    @State private var selection: SettingsTab

    init(settings: AppSettings, onClearHistory: (() -> Void)? = nil, initialTab: SettingsTab = .general) {
        self.settings = settings
        self.onClearHistory = onClearHistory
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
                    .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
            }
        }
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: generalPane
        case .shortcuts: shortcutsPane
        case .destination: destinationPane
        case .presets: presetsPane
        case .appearance: appearancePane
        case .privacy: privacyPane
        }
    }

    // MARK: Général.

    private var generalPane: some View {
        Form {
            Picker("Destination par défaut", selection: $settings.defaultDestination) {
                ForEach(Destination.allCases) { destination in
                    Text(destination.title).tag(destination)
                }
            }
            Toggle("Ouvrir au démarrage", isOn: $settings.launchAtLogin)
            HStack {
                Text("Miniature visible")
                Slider(value: $settings.toastDuration, in: 2...10, step: 1)
                Text("\(Int(settings.toastDuration)) s").monospacedDigit()
            }
            Toggle("Son d'obturateur", isOn: $settings.shutterSound)
            Toggle("Audio système (vidéo)", isOn: $settings.recordSystemAudio)
        }
        .formStyle(.grouped)
    }

    // MARK: Raccourcis.

    private var shortcutsPane: some View {
        Form {
            ShortcutRecorderField(label: "Ouvrir Focale", shortcut: $settings.mainShortcut)
            ShortcutRecorderField(label: "Historique", shortcut: $settings.historyShortcut)
            ShortcutRecorderField(label: "Répéter la dernière zone", shortcut: $settings.repeatShortcut)
            HStack {
                Spacer()
                Button("Réinitialiser") {
                    settings.mainShortcut = .defaultMain
                    settings.historyShortcut = .defaultHistory
                    settings.repeatShortcut = .defaultRepeat
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Destination.

    private var destinationPane: some View {
        Form {
            FolderRow(path: $settings.saveFolderPath)
            Picker("Format", selection: $settings.saveFormat) {
                ForEach(ImageFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            Picker("Format vidéo", selection: $settings.videoFormat) {
                ForEach(VideoFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            TextField("Motif de nom", text: $settings.fileNamePattern, prompt: Text("Focale {date} {heure}"))
            LabeledContent("Aperçu") {
                Text(settings.sampleFileName())
                    .font(.focaleMono)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Préréglages.

    private var presetsPane: some View {
        Form {
            ForEach(PresetKind.allCases) { preset in
                HStack {
                    Image(systemName: preset.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(preset.title).font(.focaleLabel)
                        Text(preset.detail)
                            .font(.focaleCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if settings.activePreset == preset {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.focaleSuccess)
                    } else {
                        Button("Appliquer") { settings.applyPreset(preset) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apparence.

    private var appearancePane: some View {
        Form {
            Picker("Thème", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Aperçu") {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.focaleBackground)
                        .frame(width: 60, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.secondary.opacity(0.3))
                        )
                    Capsule()
                        .fill(LinearGradient.focaleAccent)
                        .frame(width: 60, height: 36)
                }
            }
            Text("Les animations suivent le réglage système « Réduire les animations ».")
                .font(.focaleCaption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: Confidentialité.

    private var privacyPane: some View {
        Form {
            LabeledContent("Traitement") {
                Text("100 % local — aucune image ne quitte cet appareil.")
                    .font(.focaleBody)
            }
            Toggle("Partager des statistiques anonymes", isOn: $settings.telemetryEnabled)
            HStack {
                Spacer()
                Button("Effacer l'historique…", role: .destructive) { onClearHistory?() }
                    .disabled(onClearHistory == nil)
            }
            LabeledContent("Version") {
                Text("Focale 1.0 (phase UI)")
                    .font(.focaleBody)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Choix du dossier d'enregistrement.

private struct FolderRow: View {
    @Binding var path: String
    @State private var showPicker = false

    var body: some View {
        LabeledContent("Dossier") {
            HStack {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                Button("Choisir…") { showPicker = true }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                path = url.path(percentEncoded: false)
            }
        }
    }
}

// MARK: - Enregistreur de raccourci clavier.

struct ShortcutRecorderField: View {
    let label: String
    @Binding var shortcut: Shortcut
    @State private var capture = ShortcutCapture()

    var body: some View {
        LabeledContent(label) {
            Button {
                capture.start(
                    onCaptured: { shortcut = $0 },
                    onCancelled: {}
                )
            } label: {
                Text(capture.isCapturing ? "Appuyez sur une combinaison…" : shortcut.displayString)
                    .font(.focaleMono)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .onDisappear { capture.stop() }
        }
    }
}

@Observable
@MainActor
final class ShortcutCapture {
    private(set) var isCapturing = false
    private var monitor: Any?
    private var onCaptured: ((Shortcut) -> Void)?
    private var onCancelled: (() -> Void)?

    func start(onCaptured: @escaping (Shortcut) -> Void, onCancelled: @escaping () -> Void) {
        stop()
        self.onCaptured = onCaptured
        self.onCancelled = onCancelled
        isCapturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isCapturing = false
        onCaptured = nil
        onCancelled = nil
    }

    private func handle(event: NSEvent) {
        guard isCapturing else { return }
        if event.keyCode == 53 { // Échap : annuler.
            let callback = onCancelled
            stop()
            callback?()
            return
        }
        let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let shortcut = Shortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags.intersection(allowed).rawValue,
            characters: event.charactersIgnoringModifiers ?? ""
        )
        let callback = onCaptured
        stop()
        callback?(shortcut)
    }
}

#Preview("Réglages") {
    SettingsView(settings: AppSettings())
}
