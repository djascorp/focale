import Foundation
import SwiftData
import SwiftUI

// MARK: - État global partagé.

@Observable
@MainActor
final class AppState {
    let settings: AppSettings
    let history: HistoryStore

    var mode: CaptureMode = .region
    var destination: Destination
    var timer: CaptureTimerOption = .off
    var lastRegion: CGRect?
    var editorShot: CapturedShot?

    /// Galerie de démonstration (la vraie répétition vit dans CaptureSession).
    var canRepeatLast: Bool { lastRegion != nil }

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.destination = settings.defaultDestination
        self.history = HistoryStore.production()
    }
}

// MARK: - Magasin d'historique persistant (SwiftData, recherche plein texte sur le nom + OCR).

@Observable
@MainActor
final class HistoryStore {
    private let context: ModelContext
    var shots: [CapturedShot] = []
    var searchText = ""

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    /// Magasin réel : base Application Support, repli mémoire si indisponible.
    static func production() -> HistoryStore {
        if let container = try? Self.container(inMemory: false) {
            return HistoryStore(context: ModelContext(container))
        }
        return HistoryStore(context: ModelContext(try! Self.container(inMemory: true)))
    }

    /// Magasin de prévisualisation : mémoire + données fictives.
    static func preview() -> HistoryStore {
        let store = HistoryStore(context: ModelContext(try! Self.container(inMemory: true)))
        for shot in CapturedShot.mockSet() {
            store.add(shot)
        }
        return store
    }

    private static func container(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([ShotRecord.self])
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let directory = folder.appendingPathComponent("Focale", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("History.store"))
        return try ModelContainer(for: schema, configurations: configuration)
    }

    func reload() {
        var descriptor = FetchDescriptor<ShotRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 500
        let records = (try? context.fetch(descriptor)) ?? []
        shots = records.compactMap(CapturedShot.init(record:))
    }

    private func save() {
        try? context.save()
    }

    private func record(for id: CapturedShot.ID) -> ShotRecord? {
        var descriptor = FetchDescriptor<ShotRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func add(_ shot: CapturedShot) {
        guard let record = shot.makeRecord() else { return }
        context.insert(record)
        pruneIfNeeded()
        save()
        reload()
    }

    func remove(_ id: CapturedShot.ID) {
        if let record = record(for: id) {
            context.delete(record)
            save()
        }
        shots.removeAll { $0.id == id }
    }

    func togglePin(_ id: CapturedShot.ID) {
        if let record = record(for: id) {
            record.pinned.toggle()
            save()
        }
        if let index = shots.firstIndex(where: { $0.id == id }) {
            shots[index].pinned.toggle()
        }
    }

    func replaceImage(of id: CapturedShot.ID, with image: NSImage) {
        guard let data = Images.pngData(from: image) else { return }
        if let record = record(for: id) {
            record.imageData = data
            save()
        }
        if let index = shots.firstIndex(where: { $0.id == id }) {
            shots[index].image = image
        }
    }

    /// Conserve au plus 300 enregistrements (les épinglés ne sont jamais purgés).
    private func pruneIfNeeded() {
        var descriptor = FetchDescriptor<ShotRecord>(
            predicate: #Predicate { $0.pinned == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 10_000
        let unpinned = (try? context.fetch(descriptor)) ?? []
        if unpinned.count > 300 {
            for record in unpinned.dropFirst(300) {
                context.delete(record)
            }
        }
    }

    var filtered: [CapturedShot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return shots }
        return shots.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.ocrText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var pinned: [CapturedShot] { filtered.filter(\.pinned) }

    /// Captures non épinglées regroupées par jour, ordre antéchronologique.
    var daySections: [(title: String, shots: [CapturedShot])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered.filter { !$0.pinned }) { shot in
            calendar.startOfDay(for: shot.date)
        }
        return groups.keys.sorted(by: >).map { day in
            (title: Self.dayTitle(for: day), shots: (groups[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    private static func dayTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Aujourd'hui") }
        if calendar.isDateInYesterday(day) { return String(localized: "Hier") }
        return day.formatted(date: .complete, time: .omitted)
    }
}
