import AppKit
import SwiftUI

// MARK: - Modèle de l'éditeur : calques, brouillon, sélection, annuler/rétablir.

@Observable
@MainActor
final class EditorModel {
    var baseImage: NSImage
    var baseSize: CGSize

    var layers: [AnnotationLayer] = []
    var draft: AnnotationLayer?
    var selectedID: AnnotationLayer.ID?

    var tool: AnnotationTool = .select
    var stroke: AnnotColor = .red
    var lineWidth: CGFloat = 4
    var opacity: Double = 1
    var fontSize: CGFloat = 28
    var blurRadius: Double = 14
    var pixelSize: Double = 16
    var loupeRadius: CGFloat = 70
    var loupeZoom: CGFloat = 2

    private(set) var numberCounter = 1
    private var undoStack: [(base: NSImage, layers: [AnnotationLayer], counter: Int)] = []
    private var redoStack: [(base: NSImage, layers: [AnnotationLayer], counter: Int)] = []

    init(baseImage: NSImage) {
        self.baseImage = baseImage
        baseSize = baseImage.size.width > 0 ? baseImage.size : CGSize(width: 800, height: 600)
    }

    // MARK: Sélection.

    var selected: AnnotationLayer? {
        layers.first { $0.id == selectedID }
    }

    func updateSelected(_ mutate: (inout AnnotationLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        mutate(&layers[index])
    }

    @discardableResult
    func select(at point: CGPoint) -> Bool {
        if let hit = layers.last(where: { $0.bounds.contains(point) }) {
            selectedID = hit.id
            return true
        }
        selectedID = nil
        return false
    }

    func moveSelected(by delta: CGPoint) {
        guard let index = layers.firstIndex(where: { $0.id == selectedID }) else { return }
        layers[index].start.x += delta.x
        layers[index].start.y += delta.y
        layers[index].end.x += delta.x
        layers[index].end.y += delta.y
    }

    func beginMove() { pushUndo() }

    func deleteSelected() {
        guard selectedID != nil else { return }
        pushUndo()
        layers.removeAll { $0.id == selectedID }
        selectedID = nil
    }

    func bringSelectedForward() {
        guard let index = layers.firstIndex(where: { $0.id == selectedID }), index < layers.count - 1 else { return }
        pushUndo()
        layers.swapAt(index, index + 1)
    }

    func sendSelectedBackward() {
        guard let index = layers.firstIndex(where: { $0.id == selectedID }), index > 0 else { return }
        pushUndo()
        layers.swapAt(index, index - 1)
    }

    // MARK: Annuler / rétablir.

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func pushUndo() {
        undoStack.append((base: baseImage, layers: layers, counter: numberCounter))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append((base: baseImage, layers: layers, counter: numberCounter))
        baseImage = previous.base
        baseSize = previous.base.size
        layers = previous.layers
        numberCounter = previous.counter
        selectedID = nil
        draft = nil
        cropRect = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((base: baseImage, layers: layers, counter: numberCounter))
        baseImage = next.base
        baseSize = next.base.size
        layers = next.layers
        numberCounter = next.counter
        selectedID = nil
        draft = nil
        cropRect = nil
    }

    // MARK: Création (formes tracées).

    func startDraft(at point: CGPoint) {
        guard let kind = tool.vectorKind else { return }
        draft = AnnotationLayer(
            vectorKind: kind,
            start: point, end: point,
            color: stroke, lineWidth: lineWidth, opacity: opacity, fontSize: fontSize
        )
    }

    func updateDraft(to point: CGPoint) {
        draft?.end = point
    }

    func finishDraft() {
        defer { draft = nil }
        guard var layer = draft else { return }
        let rect = layer.normalizedRect
        guard rect.width >= 3 || rect.height >= 3 else { return }
        pushUndo()
        layers.append(layer)
        selectedID = layer.id
    }

    // MARK: Recadrage.

    var cropRect: CGRect?

    func startCrop(at point: CGPoint) {
        cropRect = CGRect(origin: point, size: .zero)
    }

    func updateCrop(to point: CGPoint) {
        guard let origin = cropRect?.origin else { return }
        cropRect = CGRect(
            x: min(origin.x, point.x), y: min(origin.y, point.y),
            width: abs(point.x - origin.x), height: abs(point.y - origin.y)
        )
    }

    func cancelCrop() {
        cropRect = nil
    }

    func finishCrop() {
        defer { cropRect = nil }
        guard let rect = cropRect, rect.width >= 8, rect.height >= 8 else { return }
        applyCrop(rect)
    }

    private func applyCrop(_ rect: CGRect) {
        let clamped = rect.intersection(CGRect(origin: .zero, size: baseSize))
        guard clamped.width >= 8, clamped.height >= 8 else { return }
        pushUndo()
        if let cg = Images.cgImage(from: baseImage) {
            let scale = CGFloat(cg.width) / max(baseSize.width, 1)
            let flipped = Geometry.flipY(rect: clamped, containerHeight: baseSize.height)
            let raw = CGRect(
                x: (flipped.minX * scale).rounded(),
                y: (flipped.minY * scale).rounded(),
                width: (flipped.width * scale).rounded(),
                height: (flipped.height * scale).rounded()
            )
            let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            let pixels = raw.integral.intersection(full)
            if !pixels.isNull, let cropped = cg.cropping(to: pixels) {
                baseImage = NSImage(cgImage: cropped, size: clamped.size)
                baseSize = clamped.size
            }
        }
        for index in layers.indices {
            layers[index].start.x -= clamped.minX
            layers[index].start.y -= clamped.minY
            layers[index].end.x -= clamped.minX
            layers[index].end.y -= clamped.minY
        }
        let bounds = CGRect(origin: .zero, size: baseSize)
        layers.removeAll { !$0.bounds.intersects(bounds) }
    }

    // MARK: Création (clic) : numéro, texte, flou, pixellisation, loupe.

    func click(at point: CGPoint) {
        switch tool {
        case .select:
            select(at: point)
        case .number:
            pushUndo()
            let layer = AnnotationLayer(
                vectorKind: .number, start: point, end: point,
                number: numberCounter, color: stroke,
                lineWidth: lineWidth, opacity: opacity, fontSize: fontSize
            )
            numberCounter += 1
            layers.append(layer)
            selectedID = layer.id
        case .text:
            pushUndo()
            let layer = AnnotationLayer(
                vectorKind: .text, start: point, end: point,
                text: String(localized: "Texte"),
                color: stroke, lineWidth: lineWidth, opacity: opacity, fontSize: fontSize
            )
            layers.append(layer)
            selectedID = layer.id
        case .blur, .pixelate:
            let size: CGFloat = 140
            let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            placeRaster(kind: tool == .blur ? .blur : .pixelate, rect: rect)
        case .loupe:
            let rect = CGRect(
                x: point.x - loupeRadius, y: point.y - loupeRadius,
                width: loupeRadius * 2, height: loupeRadius * 2
            )
            placeRaster(kind: .loupe, rect: rect)
        case .arrow, .rectangle, .ellipse, .line, .highlighter, .crop:
            break
        }
    }

    /// Glisser-déposer avec un outil raster : pose un effet dimensionné au geste.
    func dragRaster(kind: RasterKind, rect: CGRect) {
        guard rect.width >= 8, rect.height >= 8 else { return }
        placeRaster(kind: kind, rect: rect)
    }

    private func placeRaster(kind: RasterKind, rect: CGRect) {
        let clamped = rect.intersection(CGRect(origin: .zero, size: baseSize))
        guard !clamped.isNull, clamped.width >= 4, clamped.height >= 4 else { return }
        let param: Double
        let image: NSImage?
        switch kind {
        case .blur:
            param = blurRadius
            image = Images.blurred(image: baseImage, rect: clamped, radius: blurRadius)
        case .pixelate:
            param = pixelSize
            image = Images.pixelated(image: baseImage, rect: clamped, scale: pixelSize)
        case .loupe:
            param = loupeZoom
            image = Images.loupe(
                image: baseImage,
                center: CGPoint(x: clamped.midX, y: clamped.midY),
                radius: min(clamped.width, clamped.height) / 2,
                zoom: loupeZoom
            )
        }
        guard let image else { return }
        pushUndo()
        let layer = AnnotationLayer(
            rasterKind: kind, rasterImage: image, rasterParam: param,
            start: clamped.origin,
            end: CGPoint(x: clamped.maxX, y: clamped.maxY),
            color: stroke, lineWidth: lineWidth, opacity: opacity, fontSize: fontSize
        )
        layers.append(layer)
        selectedID = layer.id
    }

    /// Recalcule l'effet raster sélectionné après un changement de paramètre.
    func refreshSelectedRaster() {
        guard let index = layers.firstIndex(where: { $0.id == selectedID }),
              let kind = layers[index].rasterKind else { return }
        let rect = layers[index].normalizedRect
        let param: Double
        let image: NSImage?
        switch kind {
        case .blur:
            param = blurRadius
            image = Images.blurred(image: baseImage, rect: rect, radius: blurRadius)
        case .pixelate:
            param = pixelSize
            image = Images.pixelated(image: baseImage, rect: rect, scale: pixelSize)
        case .loupe:
            param = loupeZoom
            image = Images.loupe(
                image: baseImage,
                center: CGPoint(x: rect.midX, y: rect.maxY - rect.height / 2),
                radius: min(rect.width, rect.height) / 2,
                zoom: loupeZoom
            )
        }
        guard let image else { return }
        layers[index].rasterImage = image
        layers[index].rasterParam = param
    }

    // MARK: Rendu final (copie / enregistrement).

    func renderedImage() -> NSImage {
        // Étape 1 : composition en coordonnées origine-haut-gauche via drawingHandler.
        let base = baseImage
        let snapshot = layers
        let size = baseSize
        let flipped = NSImage(size: size, flipped: true) { rect in
            base.draw(in: rect)
            for layer in snapshot {
                Self.draw(layer)
            }
            return true
        }
        // Étape 2 : normalisation (orientation standard pour l'export).
        let final = NSImage(size: size)
        final.lockFocus()
        flipped.draw(in: CGRect(origin: .zero, size: size))
        final.unlockFocus()
        return final
    }

    private static func draw(_ layer: AnnotationLayer) {
        if let raster = layer.rasterImage {
            raster.draw(
                in: layer.normalizedRect,
                from: CGRect(origin: .zero, size: raster.size),
                operation: .sourceOver,
                fraction: layer.opacity
            )
            return
        }
        guard let kind = layer.vectorKind else { return }
        let color = layer.color.nsColor.withAlphaComponent(layer.opacity)
        color.set()
        switch kind {
        case .arrow:
            let path = NSBezierPath()
            path.move(to: layer.start)
            path.line(to: layer.end)
            path.lineWidth = layer.lineWidth
            path.lineCapStyle = .round
            path.stroke()
            drawArrowHead(from: layer.start, to: layer.end, width: layer.lineWidth, color: color)
        case .line:
            let path = NSBezierPath()
            path.move(to: layer.start)
            path.line(to: layer.end)
            path.lineWidth = layer.lineWidth
            path.lineCapStyle = .round
            path.stroke()
        case .highlight:
            color.withAlphaComponent(layer.opacity * 0.45).set()
            let path = NSBezierPath()
            path.move(to: layer.start)
            path.line(to: layer.end)
            path.lineWidth = layer.lineWidth * 3
            path.lineCapStyle = .round
            path.stroke()
        case .rectangle:
            let path = NSBezierPath(rect: layer.normalizedRect)
            path.lineWidth = layer.lineWidth
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: layer.normalizedRect)
            path.lineWidth = layer.lineWidth
            path.stroke()
        case .text:
            (layer.text as NSString).draw(
                at: layer.start,
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: layer.fontSize, weight: .semibold),
                    .foregroundColor: color,
                ]
            )
        case .number:
            let bounds = layer.bounds
            let circle = NSBezierPath(ovalIn: bounds)
            color.setFill()
            circle.fill()
            let label = "\(layer.number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: layer.fontSize, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let textSize = label.size(withAttributes: attributes)
            label.draw(
                at: CGPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2),
                withAttributes: attributes
            )
        }
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10, width * 3.2)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(
            x: end.x - length * cos(angle - 0.42),
            y: end.y - length * sin(angle - 0.42)
        ))
        head.line(to: CGPoint(
            x: end.x - length * cos(angle + 0.42),
            y: end.y - length * sin(angle + 0.42)
        ))
        head.close()
        color.setFill()
        head.fill()
    }
}

// MARK: - Correspondance outil → forme vectorielle.

private extension AnnotationTool {
    var vectorKind: VectorKind? {
        switch self {
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .highlighter: .highlight
        case .select, .text, .blur, .pixelate, .number, .loupe, .crop: nil
        }
    }
}
