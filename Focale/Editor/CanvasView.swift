import SwiftUI

// MARK: - Canevas d'annotation : image + calques + gestes souris.

struct CanvasView: View {
    @Bindable var model: EditorModel

    @State private var dragStart: CGPoint?
    @State private var lastPoint: CGPoint?
    @State private var isMovingSelection = false

    var body: some View {
        GeometryReader { proxy in
            let mapping = Geometry.aspectFit(content: model.baseSize, in: proxy.size)
            ZStack {
                // Fond neutre.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                // Image de base + calques.
                Canvas { context, _ in
                    context.translateBy(x: mapping.offset.x, y: mapping.offset.y)
                    context.scaleBy(x: mapping.scale, y: mapping.scale)
                    context.draw(Image(nsImage: model.baseImage), in: CGRect(origin: .zero, size: model.baseSize))
                    for layer in model.layers {
                        LayerRenderer.draw(layer, in: &context)
                    }
                    if let draft = model.draft {
                        LayerRenderer.draw(draft, in: &context)
                    }
                    let inverse = 1 / mapping.scale
                    if model.tool == .crop, let crop = model.cropRect {
                        var dim = Path()
                        dim.addRect(CGRect(origin: .zero, size: model.baseSize))
                        dim.addRect(crop)
                        context.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                        context.stroke(Path(crop), with: .color(.white), lineWidth: 1.5 * inverse)
                    }
                    if let selected = model.selected {
                        context.stroke(
                            Path(selected.bounds),
                            with: .color(.blue),
                            style: StrokeStyle(lineWidth: 1.5 * inverse, dash: [6 * inverse, 4 * inverse])
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(canvasGesture(mapping: mapping))
                .onHover { hovering in
                    if hovering {
                        NSCursor.crosshair.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .onKeyPress(phases: .down) { press in
            if press.key == .delete || press.key.character == "\u{7F}" {
                model.deleteSelected()
                return .handled
            }
            if press.key == .escape {
                model.selectedID = nil
                model.draft = nil
                return .handled
            }
            return .ignored
        }
        .accessibilityLabel("Canevas d'annotation")
    }

    private func canvasGesture(mapping: (scale: CGFloat, offset: CGPoint, fitted: CGSize)) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = imagePoint(from: value.location, mapping: mapping)
                if dragStart == nil {
                    dragStart = point
                    lastPoint = point
                    beginInteraction(at: point)
                } else if let previous = lastPoint {
                    let delta = CGPoint(x: point.x - previous.x, y: point.y - previous.y)
                    updateInteraction(at: point, delta: delta)
                    lastPoint = point
                }
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    lastPoint = nil
                    isMovingSelection = false
                }
                let point = imagePoint(from: value.location, mapping: mapping)
                let distance = dragStart.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
                if distance < 3 {
                    // Clic : placement ou sélection.
                    model.draft = nil
                    model.cancelCrop()
                    model.click(at: point)
                    return
                }
                if model.tool.isShapeTool {
                    model.finishDraft()
                } else if model.tool == .crop {
                    model.finishCrop()
                } else if model.tool == .blur || model.tool == .pixelate, let origin = dragStart {
                    model.dragRaster(
                        kind: model.tool == .blur ? .blur : .pixelate,
                        rect: CGRect(
                            x: min(origin.x, point.x), y: min(origin.y, point.y),
                            width: abs(point.x - origin.x), height: abs(point.y - origin.y)
                        )
                    )
                }
            }
    }

    private func beginInteraction(at point: CGPoint) {
        if model.tool == .select {
            if model.select(at: point) {
                isMovingSelection = true
                model.beginMove()
            }
        } else if model.tool.isShapeTool {
            model.startDraft(at: point)
        } else if model.tool == .crop {
            model.startCrop(at: point)
        }
    }

    private func updateInteraction(at point: CGPoint, delta: CGPoint) {
        if isMovingSelection {
            model.moveSelected(by: delta)
        } else if model.tool.isShapeTool {
            model.updateDraft(to: point)
        } else if model.tool == .crop {
            model.updateCrop(to: point)
        }
    }

    private func imagePoint(
        from location: CGPoint,
        mapping: (scale: CGFloat, offset: CGPoint, fitted: CGSize)
    ) -> CGPoint {
        let converted = Geometry.convert(location, scale: mapping.scale, offset: mapping.offset)
        return CGPoint(
            x: min(max(converted.x, 0), model.baseSize.width),
            y: min(max(converted.y, 0), model.baseSize.height)
        )
    }
}

// MARK: - Rendu SwiftUI des calques (miroir du rendu AppKit d'export).

enum LayerRenderer {
    static func draw(_ layer: AnnotationLayer, in context: inout GraphicsContext) {
        context.drawLayer { layerContext in
            layerContext.opacity = layer.opacity
            if let raster = layer.rasterImage {
                layerContext.draw(Image(nsImage: raster), in: layer.normalizedRect)
                return
            }
            guard let kind = layer.vectorKind else { return }
            let color = layer.color.color
            switch kind {
            case .arrow:
                strokeLine(from: layer.start, to: layer.end, width: layer.lineWidth, color: color, in: &layerContext)
                drawArrowHead(from: layer.start, to: layer.end, width: layer.lineWidth, color: color, in: &layerContext)
            case .line:
                strokeLine(from: layer.start, to: layer.end, width: layer.lineWidth, color: color, in: &layerContext)
            case .highlight:
                layerContext.opacity = layer.opacity * 0.45
                strokeLine(from: layer.start, to: layer.end, width: layer.lineWidth * 3, color: color, in: &layerContext)
            case .rectangle:
                layerContext.stroke(Path(layer.normalizedRect), with: .color(color), lineWidth: layer.lineWidth)
            case .ellipse:
                layerContext.stroke(Path(ellipseIn: layer.normalizedRect), with: .color(color), lineWidth: layer.lineWidth)
            case .text:
                layerContext.draw(
                    Text(layer.text)
                        .font(.system(size: layer.fontSize, weight: .semibold))
                        .foregroundColor(color),
                    at: layer.start,
                    anchor: .topLeading
                )
            case .number:
                let bounds = layer.bounds
                layerContext.fill(Path(ellipseIn: bounds), with: .color(color))
                let label = "\(layer.number)"
                let attributes = AnnotationLayer.textAttributes(size: layer.fontSize)
                let textSize = (label as NSString).size(withAttributes: attributes)
                layerContext.draw(
                    Text(label).font(.system(size: layer.fontSize, weight: .bold)).foregroundColor(.white),
                    at: CGPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2),
                    anchor: .topLeading
                )
            }
        }
    }

    private static func strokeLine(
        from start: CGPoint, to end: CGPoint, width: CGFloat, color: Color, in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func drawArrowHead(
        from start: CGPoint, to end: CGPoint, width: CGFloat, color: Color, in context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10, width * 3.2)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - length * cos(angle - 0.42), y: end.y - length * sin(angle - 0.42)))
        head.addLine(to: CGPoint(x: end.x - length * cos(angle + 0.42), y: end.y - length * sin(angle + 0.42)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

#Preview("Canevas") {
    CanvasPreviewWrapper()
}

private struct CanvasPreviewWrapper: View {
    @State private var model: EditorModel

    init() {
        let model = EditorModel(baseImage: Images.samplePhoto(seed: 2, size: CGSize(width: 1080, height: 720)))
        model.layers = [
            AnnotationLayer(
                vectorKind: .arrow, start: CGPoint(x: 120, y: 200), end: CGPoint(x: 420, y: 320),
                color: .red, lineWidth: 6
            ),
            AnnotationLayer(
                vectorKind: .number, start: CGPoint(x: 500, y: 240), end: CGPoint(x: 500, y: 240),
                number: 1, color: .blue, fontSize: 30
            ),
        ]
        _model = State(wrappedValue: model)
    }

    var body: some View {
        CanvasView(model: model)
            .frame(width: 800, height: 560)
            .padding()
    }
}
