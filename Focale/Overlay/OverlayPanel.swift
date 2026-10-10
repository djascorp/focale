import AppKit
import SwiftUI

// MARK: - Panneau overlay : au-dessus de tout, tous les Spaces, plein écran inclus (§9.6.3).

final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Contrôleur d'overlay : état de sélection + commutation de mode.

@Observable
@MainActor
final class OverlayController {
    let screen: NSScreen
    let panel: OverlayPanel
    var selection: CGRect?
    var highlightedWindow: CGWindowID?
    var onRegion: (@MainActor (CGRect) -> Void)?
    var onWindow: (@MainActor (CGWindowID) -> Void)?
    var onDisplay: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
        panel = OverlayPanel(screen: screen)
    }

    func show(mode: CaptureMode) {
        selection = nil
        highlightedWindow = nil
        switch mode {
        case .region, .video, .scroll:
            panel.contentView = NSHostingView(rootView: RegionHostView(controller: self))
        case .window:
            panel.contentView = NSHostingView(rootView: WindowHostView(controller: self))
        case .screen:
            panel.contentView = NSHostingView(rootView: ScreenHostView(controller: self))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func commitRegion(_ rect: CGRect) { onRegion?(rect) }
    func commitWindow(_ id: CGWindowID) { onWindow?(id) }
    func commitDisplay() { onDisplay?() }
    func cancel() { onCancel?() }
}

// MARK: - Hôtes SwiftUI (ponts @MainActor vers les vues).

private struct RegionHostView: View {
    @Bindable var controller: OverlayController

    var body: some View {
        SelectionOverlayView(
            selection: $controller.selection,
            commitOnRelease: true,
            onCommit: { rect in MainActor.assumeIsolated { controller.commitRegion(rect) } },
            onCancel: { MainActor.assumeIsolated { controller.cancel() } }
        )
    }
}

private struct WindowHostView: View {
    @Bindable var controller: OverlayController

    var body: some View {
        WindowHighlightView(
            frame: controller.screen.frame,
            selection: $controller.highlightedWindow,
            onCommit: { id in MainActor.assumeIsolated { controller.commitWindow(id) } },
            onCancel: { MainActor.assumeIsolated { controller.cancel() } }
        )
    }
}

private struct ScreenHostView: View {
    @Bindable var controller: OverlayController

    var body: some View {
        ScreenClickView(
            onCommit: { MainActor.assumeIsolated { controller.commitDisplay() } },
            onCancel: { MainActor.assumeIsolated { controller.cancel() } }
        )
    }
}

// MARK: - Inventaire des fenêtres à l'écran (survol du mode Fenêtre).

enum WindowLookup {
    struct FoundWindow {
        let id: CGWindowID
        let frame: CGRect
        let owner: String
    }

    static func topWindow(at point: CGPoint) -> FoundWindow? {
        allWindows().first { $0.frame.contains(point) }
    }

    static func frame(of id: CGWindowID) -> CGRect? {
        allWindows().first { $0.id == id }?.frame
    }

    private static func allWindows() -> [FoundWindow] {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        var results: [FoundWindow] = []
        for info in list {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ourPID else { continue }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
            guard width >= 8, height >= 8 else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            results.append(FoundWindow(id: id, frame: CGRect(x: x, y: y, width: width, height: height), owner: owner))
        }
        return results
    }
}

// MARK: - Survol et choix d'une fenêtre.

struct WindowHighlightView: View {
    let frame: CGRect
    @Binding var selection: CGWindowID?
    var onCommit: (CGWindowID) -> Void
    var onCancel: () -> Void

    @State private var highlight: CGRect?
    @State private var ownerName = ""
    @State private var ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let container = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                Path { path in
                    path.addRect(container)
                    if let highlight { path.addRect(highlight) }
                }
                .fill(.black.opacity(0.25), style: FillStyle(eoFill: true))
                if let highlight {
                    Rectangle()
                        .path(in: highlight)
                        .stroke(.white, lineWidth: 2)
                    Text(ownerName)
                        .font(.focaleCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: Capsule())
                        .position(x: highlight.midX, y: max(highlight.minY - 18, 14))
                } else {
                    Text("Survolez une fenêtre — cliquez pour la capturer (Échap annule)")
                        .font(.focaleLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .position(x: container.midX, y: container.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        // Recherche fraîche au point du clic : jamais d'état périmé.
                        let global = CGPoint(
                            x: value.location.x + frame.minX,
                            y: frame.maxY - value.location.y
                        )
                        if let found = WindowLookup.topWindow(at: global) {
                            onCommit(found.id)
                        }
                    }
            )
        }
        .onReceive(ticker) { _ in updateHighlight() }
        .onKeyPress(phases: .down) { press in
            if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func updateHighlight() {
        let global = NSEvent.mouseLocation
        guard frame.contains(global),
              let found = WindowLookup.topWindow(at: global) else {
            highlight = nil
            selection = nil
            ownerName = ""
            return
        }
        let rect = CGRect(
            x: found.frame.minX - frame.minX,
            y: frame.maxY - found.frame.maxY,
            width: found.frame.width,
            height: found.frame.height
        )
        // Gardes anti-battement : ne republier que si quelque chose a changé.
        if selection != found.id { selection = found.id }
        if ownerName != found.owner { ownerName = found.owner }
        if highlight != rect { highlight = rect }
    }
}

// MARK: - Clic pour capturer l'écran.

struct ScreenClickView: View {
    var onCommit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 32))
                Text("Cliquez pour capturer cet écran")
                    .font(.focaleLabel)
                Text("Échap pour annuler")
                    .font(.focaleCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCommit)
        .onKeyPress(phases: .down) { press in
            if press.key == .escape {
                onCancel()
                return .handled
            }
            return .ignored
        }
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
