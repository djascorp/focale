import SwiftUI

// MARK: - Point d'entrée de l'application Focale (phase UI).

@main
struct FocaleApp: App {
    @State private var appState: AppState
    @State private var session: CaptureSession
    @NSApplicationDelegateAdaptor private var appDelegate: LauncherDelegate

    init() {
        let state = AppState()
        _appState = State(wrappedValue: state)
        _session = State(wrappedValue: CaptureSession(appState: state))
        appDelegate.session = session
    }

    var body: some Scene {
        Window("Focale — Galerie UI", id: "gallery") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)

        Window("Historique", id: "history") {
            HistoryWindowHost()
                .environment(appState)
        }
        .defaultSize(width: 900, height: 620)

        Window("Annoter", id: "editor") {
            EditorWindowHost()
                .environment(appState)
        }
        .defaultSize(width: 1080, height: 700)

        Settings {
            SettingsView(
                settings: appState.settings,
                onClearHistory: { appState.history.clearAll() }
            )
        }

        MenuBarExtra("Focale", systemImage: "rectangle.dashed") {
            MenuBarContent()
                .environment(appState)
                .environment(session)
        }
    }
}

// MARK: - Démarrage effectif.

// Le contenu d'un MenuBarExtra n'est instancié qu'au premier clic sur l'icône :
// sans ce délégué, raccourcis globaux, onboarding et App Intents resteraient
// inertes jusqu'à ce clic.
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    weak var session: CaptureSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        session?.start()
    }
}

// MARK: - Contenu du menu de la barre des menus.

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(CaptureSession.self) private var session
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Nouvelle capture") { session.beginCapture() }
                .keyboardShortcut("5", modifiers: [.command, .shift])
            Button("Historique") { openWindow(id: "history") }
            Button("Galerie UI (dev)") { openWindow(id: "gallery") }
            Divider()
            Button("Réglages…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quitter Focale") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear { session.start() }
    .onReceive(NotificationCenter.default.publisher(for: .focaleOpenHistory)) { _ in
        openWindow(id: "history")
    }
    .onReceive(NotificationCenter.default.publisher(for: .focaleOpenGallery)) { _ in
        openWindow(id: "gallery")
    }
    }
}

// MARK: - Hôtes des fenêtres secondaires.

private struct HistoryWindowHost: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HistoryView(
            store: appState.history,
            onAnnotate: { shot in
                appState.editorShot = shot
                openWindow(id: "editor")
            }
        )
        .frame(minWidth: 640, minHeight: 420)
    }
}

private struct EditorWindowHost: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let shot = appState.editorShot {
                EditorView(
                    shot: shot,
                    onDone: { image in
                        appState.history.replaceImage(of: shot.id, with: image)
                        dismissWindow(id: "editor")
                    },
                    onCancel: { dismissWindow(id: "editor") }
                )
            } else {
                ContentUnavailableView(
                    "Aucune image",
                    systemImage: "photo",
                    description: Text("Ouvrez une capture depuis l'historique pour l'annoter.")
                )
                .frame(minWidth: 600, minHeight: 400)
            }
        }
    }
}
