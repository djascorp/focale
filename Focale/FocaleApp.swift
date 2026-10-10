import SwiftUI

// MARK: - Point d'entrée de l'application Focale (phase UI).

@main
struct FocaleApp: App {
    @State private var appState = AppState()

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
                onClearHistory: { appState.history.shots.removeAll() }
            )
        }

        MenuBarExtra("Focale", systemImage: "rectangle.dashed") {
            MenuBarContent()
                .environment(appState)
        }
    }
}

// MARK: - Contenu du menu de la barre des menus.

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Nouvelle capture") { openWindow(id: "gallery") }
            .keyboardShortcut("5", modifiers: [.command, .shift])
        Button("Historique") { openWindow(id: "history") }
        Divider()
        Button("Réglages…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quitter Focale") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
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
