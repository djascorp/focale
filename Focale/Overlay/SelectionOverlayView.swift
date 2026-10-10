import SwiftUI

// MARK: - Superposition de sélection (§7.2.B : voile 25 %, zone révélée, loupe 8×).

struct SelectionOverlayView: View {
    @Binding var selection: CGRect?
    var background: NSImage?
    var commitOnRelease = true
    var onCommit: (CGRect) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @State private var gesture: OverlayGesture?
    @State private var hoverPoint: CGPoint?
    @State private var lockedRatio: LockedRatio = .free
    @State private var showSizeEditor = false
    @State private var sizeEditorAnchor: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            let container = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                if let background {
                    Canvas { context, size in
                        context.draw(Image(nsImage: background), in: CGRect(origin: .zero, size: size))
                    }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                }
                // Voile avec découpe (remplissage even-odd).
                Path { path in
                    path.addRect(container)
                    if let selection { path.addRect(selection) }
                }
                .fill(.black.opacity(0.25), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .gesture(dragGesture(in: container))

                if let selection {
                    selectionChrome(selection, in: container)
                }
                if let hoverPoint, let background, gesture != nil {
                    magnifier(at: hoverPoint, container: container, background: background)
                }
            }
            .onKeyPress(phases: .down) { press in
                if press.key == .escape {
                    if gesture == nil, selection != nil {
                        selection = nil
                    } else {
                        onCancel()
                    }
                    return .handled
                }
                return .ignored
            }
            .popover(isPresented: $showSizeEditor, attachmentAnchor: .point(.init(x: 0, y: 0))) {
                SizeEditorPopover(
                    selection: $selection,
                    lockedRatio: $lockedRatio
                )
            }
        }
        .cursorCrosshair()
    }

    // MARK: Chrome de sélection (liseré, poignées, pastille).

    private func selectionChrome(_ rect: CGRect, in container: CGRect) -> some View {
        ZStack {
            Rectangle()
                .path(in: rect)
                .stroke(.black.opacity(0.35), lineWidth: 3)
            Rectangle()
                .path(in: rect)
                .stroke(.white, lineWidth: 1)
            ForEach(OverlayHandle.allCases) { handle in
                Rectangle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .border(.black.opacity(0.5), width: 1)
                    .position(handle.point(in: rect))
            }
            DimensionBadge(size: rect.size)
                .position(badgePosition(for: rect, in: container))
                .onTapGesture(count: 2) {
                    sizeEditorAnchor = badgePosition(for: rect, in: container)
                    showSizeEditor = true
                }
                .help("Double-cliquer pour saisir une taille exacte (F5)")
        }
    }

    private func badgePosition(for rect: CGRect, in container: CGRect) -> CGPoint {
        let above = CGPoint(x: rect.midX, y: rect.minY - 20)
        let below = CGPoint(x: rect.midX, y: rect.maxY + 20)
        let candidate = above.y > 16 ? above : below
        return CGPoint(x: min(max(candidate.x, 90), container.width - 90), y: candidate.y)
    }

    // MARK: Loupe 8× pour l'alignement au pixel.

    private func magnifier(at point: CGPoint, container: CGRect, background: NSImage) -> some View {
        let size: CGFloat = 132
        let offset = CGPoint(x: 28, y: -size - 28)
        var origin = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        origin.x = min(max(origin.x, 8), container.width - size - 8)
        origin.y = min(max(origin.y, 8), container.height - size - 8)
        return MagnifierView(image: background, container: container, viewPoint: point, zoom: 8, size: size)
            .position(x: origin.x + size / 2, y: origin.y + size / 2)
    }

    // MARK: Gestes (création, déplacement, redimensionnement).

    private func dragGesture(in container: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                hoverPoint = value.location
                if gesture == nil {
                    if let handle = handle(at: value.location) {
                        gesture = .resizing(handle: handle, start: value.location, rect: selection ?? .zero)
                    } else if let current = selection, current.contains(value.location) {
                        gesture = .moving(start: value.location, rect: current)
                    } else {
                        gesture = .creating(origin: value.location)
                        selection = CGRect(origin: value.location, size: .zero)
                    }
                }
                guard let current = gesture else { return }
                switch current {
                case .creating(let origin):
                    var rect = CGRect(
                        x: min(origin.x, value.location.x),
                        y: min(origin.y, value.location.y),
                        width: abs(value.location.x - origin.x),
                        height: abs(value.location.y - origin.y)
                    )
                    rect = Geometry.clamp(rect, to: container)
                    selection = applyLockedRatio(to: rect, anchor: origin)
                case .moving(let start, let initial):
                    let delta = CGPoint(x: value.location.x - start.x, y: value.location.y - start.y)
                    selection = Geometry.clamp(initial.offsetBy(dx: delta.x, dy: delta.y), to: container)
                case .resizing(let handle, let start, let initial):
                    let delta = CGPoint(x: value.location.x - start.x, y: value.location.y - start.y)
                    var rect = handle.apply(delta: delta, to: initial)
                    rect = Geometry.clamp(rect, to: container)
                    selection = applyLockedRatio(to: rect, anchor: handle.oppositePoint(in: initial))
                }
            }
            .onEnded { value in
                defer { gesture = nil }
                guard let rect = selection else { return }
                if rect.width < 4 || rect.height < 4 {
                    selection = nil
                    return
                }
                if commitOnRelease, case .creating = gesture {
                    onCommit(rect)
                }
            }
    }

    private func handle(at point: CGPoint) -> OverlayHandle? {
        guard let selection else { return nil }
        return OverlayHandle.allCases.first { handle in
            CGRect(center: handle.point(in: selection), size: CGSize(width: 16, height: 16)).contains(point)
        }
    }

    private func applyLockedRatio(to rect: CGRect, anchor: CGPoint) -> CGRect {
        guard let ratio = lockedRatio.value else { return rect }
        var adjusted = rect
        let height = adjusted.width / ratio
        if anchor.y <= rect.midY {
            adjusted.size.height = height
        } else {
            adjusted.origin.y = adjusted.maxY - height
            adjusted.size.height = height
        }
        return adjusted
    }
}

// MARK: - Gestes et poignées.

private enum OverlayGesture {
    case creating(origin: CGPoint)
    case moving(start: CGPoint, rect: CGRect)
    case resizing(handle: OverlayHandle, start: CGPoint, rect: CGRect)
}

enum LockedRatio: String, CaseIterable, Identifiable {
    case free, r16x9, r4x3, r1x1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: String(localized: "Libre")
        case .r16x9: "16:9"
        case .r4x3: "4:3"
        case .r1x1: "1:1"
        }
    }

    var value: CGFloat? {
        switch self {
        case .free: nil
        case .r16x9: 16 / 9
        case .r4x3: 4 / 3
        case .r1x1: 1
        }
    }
}

enum OverlayHandle: CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var id: Self { self }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func oppositePoint(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: OverlayHandle.bottomRight.point(in: rect)
        case .top: OverlayHandle.bottom.point(in: rect)
        case .topRight: OverlayHandle.bottomLeft.point(in: rect)
        case .right: OverlayHandle.left.point(in: rect)
        case .bottomRight: OverlayHandle.topLeft.point(in: rect)
        case .bottom: OverlayHandle.top.point(in: rect)
        case .bottomLeft: OverlayHandle.topRight.point(in: rect)
        case .left: OverlayHandle.right.point(in: rect)
        }
    }

    func apply(delta: CGPoint, to rect: CGRect) -> CGRect {
        var next = rect
        switch self {
        case .topLeft:
            next.origin.x += delta.x; next.origin.y += delta.y
            next.size.width -= delta.x; next.size.height -= delta.y
        case .top:
            next.origin.y += delta.y; next.size.height -= delta.y
        case .topRight:
            next.origin.y += delta.y; next.size.width += delta.x; next.size.height -= delta.y
        case .right:
            next.size.width += delta.x
        case .bottomRight:
            next.size.width += delta.x; next.size.height += delta.y
        case .bottom:
            next.size.height += delta.y
        case .bottomLeft:
            next.origin.x += delta.x; next.size.width -= delta.x; next.size.height += delta.y
        case .left:
            next.origin.x += delta.x; next.size.width -= delta.x
        }
        next.size.width = max(next.size.width, 1)
        next.size.height = max(next.size.height, 1)
        return next
    }
}

// MARK: - Loupe d'alignement.

private struct MagnifierView: View {
    let image: NSImage
    let container: CGRect
    let viewPoint: CGPoint
    let zoom: CGFloat
    let size: CGFloat

    var body: some View {
        let mapping = Geometry.aspectFill(content: image.size, in: container.size)
        let imagePoint = Geometry.convert(viewPoint, scale: mapping.scale, offset: mapping.offset)
        Canvas { context, canvasSize in
            let cropWidth = canvasSize.width / zoom
            context.translateBy(x: canvasSize.width / 2 - imagePoint.x * zoom, y: canvasSize.height / 2 - imagePoint.y * zoom)
            context.scaleBy(x: zoom, y: zoom)
            context.draw(Image(nsImage: image), in: CGRect(origin: .zero, size: image.size))
            // Grille au pixel.
            var grid = Path()
            let fromX = Int((imagePoint.x - cropWidth).rounded()) - 1
            let toX = Int((imagePoint.x + cropWidth).rounded()) + 1
            let fromY = Int((imagePoint.y - cropWidth).rounded()) - 1
            let toY = Int((imagePoint.y + cropWidth).rounded()) + 1
            for x in fromX...toX {
                grid.move(to: CGPoint(x: CGFloat(x), y: CGFloat(fromY)))
                grid.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(toY)))
            }
            for y in fromY...toY {
                grid.move(to: CGPoint(x: CGFloat(fromX), y: CGFloat(y)))
                grid.addLine(to: CGPoint(x: CGFloat(toX), y: CGFloat(y)))
            }
            context.stroke(grid, with: .color(.white.opacity(0.25)), lineWidth: 1 / zoom)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .overlay(
            ZStack {
                Rectangle().fill(.red).frame(width: size, height: 1)
                Rectangle().fill(.red).frame(width: 1, height: size)
            }
        )
        .shadow(radius: 12)
    }
}

// MARK: - Saisie de taille exacte (F5).

private struct SizeEditorPopover: View {
    @Binding var selection: CGRect?
    @Binding var lockedRatio: LockedRatio
    @State private var widthText = ""
    @State private var heightText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zone précise")
                .font(.focaleHeadline)
            HStack {
                TextField("Largeur", text: $widthText)
                    .frame(width: 70)
                    .onSubmit(applySize)
                Text("×").foregroundStyle(.secondary)
                TextField("Hauteur", text: $heightText)
                    .frame(width: 70)
                    .onSubmit(applySize)
                Button("Appliquer", action: applySize)
            }
            .textFieldStyle(.roundedBorder)
            Picker("Ratio", selection: $lockedRatio) {
                ForEach(LockedRatio.allCases) { ratio in
                    Text(ratio.title).tag(ratio)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: lockedRatio) { _, newValue in
                guard let ratio = newValue.value, var rect = selection, rect.width > 0 else { return }
                rect.size.height = rect.width / ratio
                selection = rect
                syncFields(with: rect)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            if let selection { syncFields(with: selection) }
        }
    }

    private func syncFields(with rect: CGRect) {
        widthText = String(Int(rect.width.rounded()))
        heightText = String(Int(rect.height.rounded()))
    }

    private func applySize() {
        guard var rect = selection,
              let width = Double(widthText), let height = Double(heightText),
              width >= 1, height >= 1 else { return }
        rect.size = CGSize(width: width, height: height)
        selection = rect
    }
}

private extension CGRect {
    init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

private extension View {
    func cursorCrosshair() -> some View {
        onHover { hovering in
            if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
        }
    }
}

#Preview("Overlay de sélection") {
    @Previewable @State var selection: CGRect? = CGRect(x: 140, y: 120, width: 480, height: 300)
    return SelectionOverlayView(
        selection: $selection,
        background: Images.sampleDesktop(size: CGSize(width: 900, height: 600)),
        commitOnRelease: false
    )
    .frame(width: 900, height: 600)
}
