import AppIntents

// MARK: - Automatisation Raccourcis / Spotlight (F14).

@MainActor
final class FocaleIntentHandler {
    static let shared = FocaleIntentHandler()
    weak var session: CaptureSession?

    func requestCapture(_ selection: SelectionMode) {
        guard let session, !session.isActive else { return }
        session.appState.setSelection(selection)
        session.beginCapture()
    }

    func requestRepeat() {
        session?.repeatLast()
    }
}

struct CaptureAreaIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Area with Focale"
    static let description = IntentDescription("Opens Focale to capture an area.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocaleIntentHandler.shared.requestCapture(.region)
        }
        return .result()
    }
}

struct CaptureWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Window with Focale"
    static let description = IntentDescription("Opens Focale to capture a window.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocaleIntentHandler.shared.requestCapture(.window)
        }
        return .result()
    }
}

struct CaptureScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Screen with Focale"
    static let description = IntentDescription("Opens Focale to capture a screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocaleIntentHandler.shared.requestCapture(.screen)
        }
        return .result()
    }
}

struct RepeatCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Repeat Last Capture with Focale"
    static let description = IntentDescription("Repeats the last captured area.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocaleIntentHandler.shared.requestRepeat()
        }
        return .result()
    }
}

struct FocaleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureAreaIntent(),
            phrases: ["Capture an area with \(.applicationName)"],
            shortTitle: "Capture Area",
            systemImageName: "rectangle.dashed"
        )
        AppShortcut(
            intent: CaptureWindowIntent(),
            phrases: ["Capture a window with \(.applicationName)"],
            shortTitle: "Capture Window",
            systemImageName: "macwindow"
        )
        AppShortcut(
            intent: CaptureScreenIntent(),
            phrases: ["Capture the screen with \(.applicationName)"],
            shortTitle: "Capture Screen",
            systemImageName: "display"
        )
    }
}
