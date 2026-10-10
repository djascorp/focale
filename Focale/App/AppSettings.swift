import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Raccourci clavier enregistré (phase UI : persistance UserDefaults).

struct Shortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifierFlags: UInt
    var characters: String

    static let defaultMain = Shortcut(keyCode: 23, modifierFlags: 0x100000 | 0x20000, characters: "5")
    static let defaultHistory = Shortcut(keyCode: 4, modifierFlags: 0x100000 | 0x20000, characters: "h")
    static let defaultRepeat = Shortcut(keyCode: 15, modifierFlags: 0x100000 | 0x20000, characters: "r")

    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + characters.uppercased()
    }
}

// MARK: - Réglages persistés.

@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    var defaultDestination: Destination {
        didSet { defaults.set(defaultDestination.rawValue, forKey: "focale.destination") }
    }
    var toastDuration: Double {
        didSet { defaults.set(toastDuration, forKey: "focale.toastDuration") }
    }
    var shutterSound: Bool {
        didSet { defaults.set(shutterSound, forKey: "focale.shutterSound") }
    }
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "focale.launchAtLogin")
            applyLaunchAtLogin()
        }
    }
    var saveFormat: ImageFormat {
        didSet { defaults.set(saveFormat.rawValue, forKey: "focale.saveFormat") }
    }
    var saveFolderPath: String {
        didSet { defaults.set(saveFolderPath, forKey: "focale.saveFolder") }
    }
    var fileNamePattern: String {
        didSet { defaults.set(fileNamePattern, forKey: "focale.fileNamePattern") }
    }
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: "focale.appearance") }
    }
    var telemetryEnabled: Bool {
        didSet { defaults.set(telemetryEnabled, forKey: "focale.telemetry") }
    }
    var activePreset: PresetKind? {
        didSet { defaults.set(activePreset?.rawValue, forKey: "focale.preset") }
    }
    var mainShortcut: Shortcut {
        didSet { storeShortcut(mainShortcut, key: "focale.shortcut.main") }
    }
    var historyShortcut: Shortcut {
        didSet { storeShortcut(historyShortcut, key: "focale.shortcut.history") }
    }
    var repeatShortcut: Shortcut {
        didSet { storeShortcut(repeatShortcut, key: "focale.shortcut.repeat") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let desktop = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? NSHomeDirectory() + "/Desktop"
        defaultDestination = Destination(rawValue: defaults.string(forKey: "focale.destination") ?? "") ?? .clipboard
        toastDuration = defaults.object(forKey: "focale.toastDuration") as? Double ?? 5
        shutterSound = defaults.object(forKey: "focale.shutterSound") as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: "focale.launchAtLogin")
        saveFormat = ImageFormat(rawValue: defaults.string(forKey: "focale.saveFormat") ?? "") ?? .png
        saveFolderPath = defaults.string(forKey: "focale.saveFolder") ?? desktop
        fileNamePattern = defaults.string(forKey: "focale.fileNamePattern") ?? "Focale {date} {heure}"
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "focale.appearance") ?? "") ?? .system
        telemetryEnabled = defaults.bool(forKey: "focale.telemetry")
        if let raw = defaults.string(forKey: "focale.preset"), let preset = PresetKind(rawValue: raw) {
            activePreset = preset
        } else {
            activePreset = nil
        }
        mainShortcut = Self.loadShortcut(defaults, key: "focale.shortcut.main") ?? .defaultMain
        historyShortcut = Self.loadShortcut(defaults, key: "focale.shortcut.history") ?? .defaultHistory
        repeatShortcut = Self.loadShortcut(defaults, key: "focale.shortcut.repeat") ?? .defaultRepeat
    }

    func applyPreset(_ preset: PresetKind) {
        activePreset = preset
        defaultDestination = preset.destination
        saveFormat = preset.format
    }

    func sampleFileName(date: Date = Date()) -> String {
        let day = date.formatted(.dateTime.year().month().day())
        let time = date.formatted(.dateTime.hour().minute().second())
        return fileNamePattern
            .replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "{heure}", with: time)
            + "." + saveFormat.rawValue
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Le service peut être indisponible en phase de développement (app non signée).
            launchAtLogin = false
            defaults.set(false, forKey: "focale.launchAtLogin")
        }
    }

    private func storeShortcut(_ shortcut: Shortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadShortcut(_ defaults: UserDefaults, key: String) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
