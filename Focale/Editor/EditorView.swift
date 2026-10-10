import AppKit
import SwiftUI

// MARK: - Fenêtre d'édition (§7.2.D : barre verticale, canevas, inspecteur).

struct EditorView: View {
    @State var model: EditorModel
    let shotName: String
    var onDone: (NSImage) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(shot: CapturedShot, onDone: @escaping (NSImage) -> Void = { _ in }, onCancel: @escaping () -> Void = {}) {
        _model = State(wrappedValue: EditorModel(baseImage: shot.image))
        shotName = shot.name
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                toolBar
                Divider()
                canvasArea
                Divider()
                InspectorView(model: model)
                    .frame(width: 248)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Color.focaleBackground)
    }

    // MARK: Barre supérieure.

    private var topBar: some View {
        HStack {
            Button("Annuler", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 1) {
                Text(shotName)
                    .font(.focaleHeadline)
                    .lineLimit(1)
                Text("\(Int(model.baseSize.width)) × \(Int(model.baseSize.height)) · \(model.layers.count) calque(s)")
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button("Terminer") { onDone(model.renderedImage()) }
                .buttonStyle(FocaleAccentButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: Barre d'outils verticale (raccourcis à une lettre).

    private var toolBar: some View {
        VStack(spacing: 2) {
            ForEach(AnnotationTool.allCases) { tool in
                toolButton(tool)
            }
            Divider().padding(.vertical, 6)
            BarIconButton(icon: "arrow.uturn.backward", size: 34, help: "Annuler (⌘Z)") {
                model.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo)
            .opacity(model.canUndo ? 1 : 0.4)
            BarIconButton(icon: "arrow.uturn.forward", size: 34, help: "Rétablir (⇧⌘Z)") {
                model.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.canRedo)
            .opacity(model.canRedo ? 1 : 0.4)
            Spacer()
            exportButtons
        }
        .padding(.vertical, 10)
        .frame(width: 54)
        .background(.ultraThinMaterial)
        .onKeyPress(phases: .down) { press in
            guard let character = press.key.character.uppercased().first else { return .ignored }
            if let tool = AnnotationTool.allCases.first(where: { $0.keyHint == String(character) }),
               tool.isImplemented {
                model.tool = tool
                return .handled
            }
            return .ignored
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        BarIconButton(
            icon: tool.icon,
            active: model.tool == tool,
            size: 34,
            help: tool.isImplemented
                ? "\(tool.title) — \(tool.hint) (\(tool.keyHint))"
                : "\(tool.title) — bientôt disponible"
        ) {
            if tool.isImplemented { model.tool = tool }
        }
        .disabled(!tool.isImplemented)
        .opacity(tool.isImplemented ? 1 : 0.35)
    }

    private var exportButtons: some View {
        VStack(spacing: 2) {
            BarIconButton(icon: "doc.on.doc", size: 34, help: "Copier le résultat (⇧⌘C)") {
                copyRendered()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            BarIconButton(icon: "square.and.arrow.down", size: 34, help: "Enregistrer (⌘S)") {
                saveRendered()
            }
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    // MARK: Zone centrale.

    private var canvasArea: some View {
        VStack(spacing: 0) {
            CanvasView(model: model)
                .padding(16)
            Divider()
            HStack {
                Text(hintText)
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.selected != nil {
                    Button("Supprimer le calque") { model.deleteSelected() }
                        .buttonStyle(.link)
                        .font(.focaleCaption)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
        }
    }

    private var hintText: String {
        switch model.tool {
        case .select: "Cliquez pour sélectionner, glissez pour déplacer. ⌫ supprime."
        case .number: "Cliquez pour poser un numéro."
        case .text: "Cliquez pour poser un texte, modifiez-le dans l'inspecteur."
        case .blur, .pixelate: "Cliquez ou tracez un rectangle pour masquer une zone."
        case .loupe: "Cliquez pour poser une loupe."
        default: "Tracez une forme sur l'image."
        }
    }

    // MARK: Export rapide.

    private func copyRendered() {
        guard let data = Images.pngData(from: model.renderedImage()) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    private func saveRendered() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = shotName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Images.pngData(from: model.renderedImage())?.write(to: url)
    }
}

#Preview("Éditeur") {
    let shots = CapturedShot.mockSet()
    return EditorView(shot: shots[1])
        .frame(width: 1080, height: 720)
}
