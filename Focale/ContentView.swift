import SwiftUI

// MARK: - Galerie UI (phase de conception : prévisualise tous les écrans, sera retirée).

enum GalleryScreen: String, CaseIterable, Identifiable {
    case bar, overlay, toast, editor, history, settings, onboarding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bar: "Barre flottante"
        case .overlay: "Sélection"
        case .toast: "Miniature"
        case .editor: "Éditeur"
        case .history: "Historique"
        case .settings: "Réglages"
        case .onboarding: "Onboarding"
        }
    }

    var icon: String {
        switch self {
        case .bar: "capsule"
        case .overlay: "rectangle.dashed"
        case .toast: "photo"
        case .editor: "pencil.tip.crop.circle"
        case .history: "clock"
        case .settings: "gearshape"
        case .onboarding: "sparkles"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var selection: GalleryScreen? = .bar
    @State private var demoSelection: CGRect? = CGRect(x: 120, y: 90, width: 460, height: 300)
    @State private var demoToast: CapturedShot?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(GalleryScreen.allCases) { screen in
                    Label(screen.title, systemImage: screen.icon)
                        .tag(screen)
                }
            }
            .navigationSplitViewColumnWidth(190)
            .navigationTitle("Focale · UI")
        } detail: {
            ZStack {
                detailView
                if let toast = demoToast {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            CaptureToastView(
                                shot: toast,
                                autoDismiss: 5,
                                onOpen: { demoToast = nil },
                                onCopy: { demoToast = nil },
                                onSave: { demoToast = nil },
                                onAnnotate: {
                                    appState.editorShot = toast
                                    openWindow(id: "editor")
                                    demoToast = nil
                                },
                                onShare: { demoToast = nil },
                                onDelete: { demoToast = nil },
                                onDismiss: { demoToast = nil }
                            )
                        }
                    }
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.focaleToast, value: demoToast?.id)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .bar {
        case .bar:
            barDemo
        case .overlay:
            overlayDemo
        case .toast:
            toastDemo
        case .editor:
            EditorView(shot: CapturedShot.mockSet()[1])
        case .history:
            HistoryView(
                store: appState.history,
                onOpen: { shot in
                    appState.editorShot = shot
                    openWindow(id: "editor")
                }
            )
        case .settings:
            SettingsView(
                settings: appState.settings,
                onClearHistory: { appState.history.clearAll() }
            )
        case .onboarding:
            OnboardingView(settings: appState.settings, onFinish: { selection = .bar })
        }
    }

    // MARK: Démo barre.

    private var barDemo: some View {
        ZStack {
            Canvas { context, size in
                if let desktop = cachedDesktop {
                    context.draw(Image(nsImage: desktop), in: CGRect(origin: .zero, size: size))
                }
            }
            VStack {
                Spacer()
                Text("Cmd + Maj + 5 — la barre apparaît avec un ressort")
                    .font(.focaleLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 12)
                CaptureBarView(
                    selection: bindingSelection,
                    kind: bindingKind,
                    destination: bindingDestination,
                    timer: bindingTimer,
                    folderName: "Bureau",
                    canRepeatLast: appState.canRepeatLast,
                    onCapture: demoCapture,
                    onRepeatLast: demoCapture,
                    onOpenSettings: { selection = .settings },
                    onCancel: {},
                    onChooseFolder: { _ in }
                )
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: Démo overlay.

    private var overlayDemo: some View {
        VStack(spacing: 0) {
            SelectionOverlayView(
                selection: $demoSelection,
                background: cachedDesktop,
                commitOnRelease: false,
                onCommit: { _ in },
                onCancel: { demoSelection = nil }
            )
            Divider()
            HStack {
                if let rect = demoSelection {
                    DimensionBadge(size: rect.size)
                    Text("Double-cliquez la pastille pour saisir une taille exacte.")
                        .font(.focaleCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Valider la zone") {
                        appState.lastRegion = rect
                        demoCapture()
                    }
                    .buttonStyle(FocaleAccentButtonStyle())
                } else {
                    Text("Tracez une zone à la souris. Échap annule.")
                        .font(.focaleCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
    }

    // MARK: Démo miniature.

    private var toastDemo: some View {
        ZStack {
            Canvas { context, size in
                if let desktop = cachedDesktop {
                    context.draw(Image(nsImage: desktop), in: CGRect(origin: .zero, size: size))
                }
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CaptureToastView(shot: CapturedShot.mockSet()[0])
                        .padding(24)
                }
            }
            VStack {
                Text("Survolez la miniature pour révéler les actions · glissez pour écarter")
                    .font(.focaleLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 24)
                Spacer()
            }
        }
    }

    // MARK: Helpers démo.

    private var cachedDesktop: NSImage? {
        Images.sampleDesktop(size: CGSize(width: 1400, height: 900))
    }

    private var bindingSelection: Binding<SelectionMode> {
        Binding(get: { appState.selection }, set: { appState.setSelection($0) })
    }

    private var bindingKind: Binding<CaptureKind> {
        Binding(get: { appState.kind }, set: { appState.setKind($0) })
    }

    private var bindingDestination: Binding<Destination> {
        Binding(get: { appState.destination }, set: { appState.destination = $0 })
    }

    private var bindingTimer: Binding<CaptureTimerOption> {
        Binding(get: { appState.timer }, set: { appState.timer = $0 })
    }

    private func demoCapture() {
        let shot = CapturedShot(
            image: Images.samplePhoto(seed: Int.random(in: 1...8), size: CGSize(width: 1280, height: 800)),
            name: "Capture \(appState.history.shots.count + 1)"
        )
        appState.history.add(shot)
        if appState.lastRegion == nil {
            appState.lastRegion = CGRect(x: 120, y: 90, width: 460, height: 300)
        }
        demoToast = shot
    }
}
