import AppKit
import Foundation
import SwiftData

// MARK: - Enregistrement persistant d'une capture (v1.1 : SwiftData, 100 % local).

@Model
final class ShotRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var name: String
    var pinned: Bool
    var ocrText: String?
    var imageData: Data
    var kindRaw: String
    var fileURLString: String?
    var duration: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        name: String,
        pinned: Bool = false,
        ocrText: String? = nil,
        imageData: Data,
        kind: ShotKind = .image,
        fileURL: URL? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.pinned = pinned
        self.ocrText = ocrText
        self.imageData = imageData
        self.kindRaw = kind.rawValue
        self.fileURLString = fileURL?.absoluteString
        self.duration = duration
    }

    var kind: ShotKind {
        get { ShotKind(rawValue: kindRaw) ?? .image }
        set { kindRaw = newValue.rawValue }
    }

    var fileURL: URL? {
        get { fileURLString.flatMap(URL.init(string:)) }
        set { fileURLString = newValue?.absoluteString }
    }
}

// MARK: - Conversions enregistrement <-> vue.

extension CapturedShot {
    init?(record: ShotRecord) {
        guard let image = NSImage(data: record.imageData) else { return nil }
        self.init(
            id: record.id,
            image: image,
            date: record.date,
            pinned: record.pinned,
            ocrText: record.ocrText,
            name: record.name,
            kind: record.kind,
            fileURL: record.fileURL,
            duration: record.duration
        )
    }

    func makeRecord() -> ShotRecord? {
        guard let data = Images.pngData(from: image) else { return nil }
        return ShotRecord(
            id: id,
            date: date,
            name: name,
            pinned: pinned,
            ocrText: ocrText,
            imageData: data,
            kind: kind,
            fileURL: fileURL,
            duration: duration
        )
    }
}
