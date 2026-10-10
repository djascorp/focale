import AppKit
import SwiftUI

// MARK: - Panneau Historique (§7.2.E : recherche, épinglage, glisser-déposer).

struct HistoryView: View {
    @Bindable var store: HistoryStore
    var onAnnotate: (CapturedShot) -> Void = { _ in }

    @State private var selectedID: CapturedShot.ID?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if store.filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                        if !store.pinned.isEmpty {
                            daySection(title: "Épinglées", shots: store.pinned)
                        }
                        ForEach(store.daySections, id: \.title) { section in
                            daySection(title: section.title, shots: section.shots)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .background(Color.focaleBackground)
        .navigationTitle("Historique")
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher (le texte OCR est indexé)", text: $store.searchText)
                .textFieldStyle(.plain)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(store.filtered.count) capture(s)")
                .font(.focaleCaption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Aucune capture",
            systemImage: "photo.on.rectangle",
            description: Text("Vos captures apparaîtront ici avec leur texte reconnu.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func daySection(title: String, shots: [CapturedShot]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.focaleHeadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(shots) { shot in
                    shotCard(shot)
                }
            }
        }
    }

    private func shotCard(_ shot: CapturedShot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                FocaleImageView(image: shot.image)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selectedID == shot.id ? Color.focaleAccentStart : .secondary.opacity(0.2),
                                    lineWidth: selectedID == shot.id ? 2 : 1)
                    )
                if shot.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.focaleAccentStart, in: Circle())
                        .padding(6)
                }
            }
            Text(shot.name)
                .font(.focaleBody)
                .lineLimit(1)
            HStack {
                Text(shot.date.formatted(date: .omitted, time: .shortened))
                Text("·")
                Text("\(Int(shot.pixelSize.width))×\(Int(shot.pixelSize.height))")
            }
            .font(.focaleCaption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            if let ocr = shot.ocrText, !ocr.isEmpty {
                Text(ocr)
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { selectedID = shot.id }
        .onTapGesture(count: 2) { onAnnotate(shot) }
        .contextMenu {
            Button("Annoter") { onAnnotate(shot) }
            Button("Copier") { copyShot(shot) }
            Button(shot.pinned ? "Désépingler" : "Épingler") { store.togglePin(shot.id) }
            Divider()
            Button("Supprimer", role: .destructive) { store.remove(shot.id) }
        }
        .onDrag { Images.itemProvider(for: shot.image, name: shot.name) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shot.name), \(shot.date.formatted())")
    }

    private func copyShot(_ shot: CapturedShot) {
        guard let data = Images.pngData(from: shot.image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }
}

#Preview("Historique") {
    HistoryView(store: HistoryStore(mock: true))
        .frame(width: 900, height: 640)
}
