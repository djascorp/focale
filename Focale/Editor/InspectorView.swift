import SwiftUI

// MARK: - Inspecteur contextuel : style, paramètres d'effet, calques.

struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                styleSection
                Divider()
                contextualSection
                if model.selected != nil {
                    Divider()
                    selectionSection
                }
                Divider()
                layersSection
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: Style.

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style").font(.focaleHeadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(AnnotColor.palette, id: \.self) { swatch in
                    Button {
                        model.stroke = swatch
                        if model.selected != nil {
                            model.updateSelected { $0.color = swatch }
                        }
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(model.stroke == swatch ? Color.focaleAccentStart : .secondary.opacity(0.3),
                                            lineWidth: model.stroke == swatch ? 2.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Couleur")
                }
            }
            labeledSlider("Épaisseur", value: Binding(
                get: { Double(model.lineWidth) },
                set: { newValue in
                    model.lineWidth = CGFloat(newValue)
                    if model.selected != nil { model.updateSelected { $0.lineWidth = CGFloat(newValue) } }
                }
            ), in: 1...20, format: "%.0f pt")
            labeledSlider("Opacité", value: Binding(
                get: { model.opacity },
                set: { newValue in
                    model.opacity = newValue
                    if model.selected != nil { model.updateSelected { $0.opacity = newValue } }
                }
            ), in: 0.1...1, format: "%.0f %%", scale: 100)
        }
    }

    // MARK: Paramètres contextuels.

    @ViewBuilder
    private var contextualSection: some View {
        switch model.tool {
        case .text:
            textSection
        case .number:
            VStack(alignment: .leading, spacing: 8) {
                Text("Numérotation").font(.focaleHeadline)
                labeledSlider("Taille", value: Binding(
                    get: { Double(model.fontSize) },
                    set: { model.fontSize = CGFloat($0) }
                ), in: 14...72, format: "%.0f pt")
                LabeledContent("Prochain numéro") {
                    Text("\(model.numberCounterNext)").monospacedDigit()
                }
                .font(.focaleBody)
            }
        case .blur:
            VStack(alignment: .leading, spacing: 8) {
                Text("Flou").font(.focaleHeadline)
                labeledSlider("Intensité", value: $model.blurRadius, in: 2...40, format: "%.0f")
                    .onChange(of: model.blurRadius) { _, _ in model.refreshSelectedRaster() }
            }
        case .pixelate:
            VStack(alignment: .leading, spacing: 8) {
                Text("Pixélisation").font(.focaleHeadline)
                labeledSlider("Taille des blocs", value: $model.pixelSize, in: 4...48, format: "%.0f")
                    .onChange(of: model.pixelSize) { _, _ in model.refreshSelectedRaster() }
            }
        case .loupe:
            VStack(alignment: .leading, spacing: 8) {
                Text("Loupe").font(.focaleHeadline)
                labeledSlider("Rayon", value: Binding(
                    get: { Double(model.loupeRadius) },
                    set: { model.loupeRadius = CGFloat($0) }
                ), in: 24...160, format: "%.0f pt")
                labeledSlider("Grossissement", value: Binding(
                    get: { Double(model.loupeZoom) },
                    set: {
                        model.loupeZoom = CGFloat($0)
                        model.refreshSelectedRaster()
                    }
                ), in: 1.5...4, format: "× %.1f")
            }
        case .select, .arrow, .rectangle, .ellipse, .line, .highlighter, .crop:
            EmptyView()
        }
        // Réglages du calque texte sélectionné, quel que soit l'outil actif.
        if let selected = model.selected, selected.vectorKind == .text, model.tool != .text {
            textSection
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Texte").font(.focaleHeadline)
            if model.selected?.vectorKind == .text {
                TextField("Contenu", text: Binding(
                    get: { model.selected?.text ?? "" },
                    set: { newValue in model.updateSelected { $0.text = newValue } }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                Text("Cliquez sur l'image pour poser un texte.")
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
            }
            labeledSlider("Taille", value: Binding(
                get: { Double(model.selected?.fontSize ?? model.fontSize) },
                set: { newValue in
                    model.fontSize = CGFloat(newValue)
                    if model.selected != nil { model.updateSelected { $0.fontSize = CGFloat(newValue) } }
                }
            ), in: 10...96, format: "%.0f pt")
        }
    }

    // MARK: Calque sélectionné.

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calque").font(.focaleHeadline)
            HStack {
                Button("Vers l'avant") { model.bringSelectedForward() }
                Button("Vers l'arrière") { model.sendSelectedBackward() }
            }
            .buttonStyle(.link)
            .font(.focaleBody)
            Button("Supprimer", role: .destructive) { model.deleteSelected() }
                .font(.focaleBody)
        }
    }

    // MARK: Liste des calques.

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calques (\(model.layers.count))").font(.focaleHeadline)
            if model.layers.isEmpty {
                Text("Aucun calque pour l'instant.")
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(model.layers.reversed()) { layer in
                        Button {
                            model.selectedID = layer.id
                        } label: {
                            HStack {
                                Image(systemName: layer.listIcon)
                                    .foregroundStyle(.secondary)
                                Text(layer.listTitle)
                                    .lineLimit(1)
                                Spacer()
                                if layer.isRaster {
                                    Image(systemName: "photo.stack")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.focaleBody)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                model.selectedID == layer.id
                                    ? Color.focaleAccentStart.opacity(0.15)
                                    : .secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Composant curseur labellisé.

    private func labeledSlider(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String, scale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.focaleBody)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale))
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }
}

private extension EditorModel {
    var numberCounterNext: Int { numberCounter }
}
