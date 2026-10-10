import SwiftUI

// MARK: - État global partagé (phase UI : navigation + démo).

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

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.destination = settings.defaultDestination
        self.history = HistoryStore(mock: true)
    }

    var canRepeatLast: Bool { lastRegion != nil }
}

// MARK: - Magasin d'historique (données fictives en phase UI, SwiftData en v1.1).

@Observable
@MainActor
final class HistoryStore {
    var shots: [CapturedShot] = []
    var searchText = ""

    init(mock: Bool) {
        if mock { shots = CapturedShot.mockSet() }
    }

    func add(_ shot: CapturedShot) {
        shots.insert(shot, at: 0)
    }

    func remove(_ id: CapturedShot.ID) {
        shots.removeAll { $0.id == id }
    }

    func togglePin(_ id: CapturedShot.ID) {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return }
        shots[index].pinned.toggle()
    }

    func replaceImage(of id: CapturedShot.ID, with image: NSImage) {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return }
        shots[index].image = image
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
