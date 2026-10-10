import AppKit
import SwiftUI

// MARK: - Modes de capture (F2).

enum CaptureMode: String, CaseIterable, Identifiable {
    case region, window, screen, video, scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .region: String(localized: "Zone")
        case .window: String(localized: "Fenêtre")
        case .screen: String(localized: "Écran")
        case .video: String(localized: "Vidéo")
        case .scroll: String(localized: "Défilement")
        }
    }

    var icon: String {
        switch self {
        case .region: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "display"
        case .video: "video"
        case .scroll: "arrow.up.and.down"
        }
    }

    var keyHint: String {
        switch self {
        case .region: "1"
        case .window: "2"
        case .screen: "3"
        case .video: "4"
        case .scroll: "5"
        }
    }
}

// MARK: - Destination (F3).

enum Destination: String, CaseIterable, Identifiable {
    case clipboard, file, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: String(localized: "Presse-papiers")
        case .file: String(localized: "Fichier")
        case .both: String(localized: "Les deux")
        }
    }

    var icon: String {
        switch self {
        case .clipboard: "clipboard"
        case .file: "folder"
        case .both: "doc.on.clipboard"
        }
    }
}

// MARK: - Minuteur (F7).

enum CaptureTimerOption: Int, CaseIterable, Identifiable {
    case off = 0, s3 = 3, s5 = 5, s10 = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Aucun")
        case .s3: "3 s"
        case .s5: "5 s"
        case .s10: "10 s"
        }
    }

    var shortLabel: String? {
        switch self {
        case .off: nil
        case .s3: "3s"
        case .s5: "5s"
        case .s10: "10s"
        }
    }

    func next() -> CaptureTimerOption {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

// MARK: - Formats et préréglages.

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum VideoFormat: String, CaseIterable, Identifiable {
    case mp4, gif

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum ShotKind: String, Codable {
    case image, video
}

enum PresetKind: String, CaseIterable, Identifiable {
    case support, tutorial, email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .support: String(localized: "Support")
        case .tutorial: String(localized: "Tutoriel")
        case .email: String(localized: "E-mail")
        }
    }

    var detail: String {
        switch self {
        case .support: String(localized: "Presse-papiers + PNG, annotation avec flou.")
        case .tutorial: String(localized: "Fichier + PNG, numérotation d'étapes.")
        case .email: String(localized: "Fichier + JPEG léger, sans annotation.")
        }
    }

    var icon: String {
        switch self {
        case .support: "lifepreserver"
        case .tutorial: "graduationcap"
        case .email: "envelope"
        }
    }

    var destination: Destination {
        switch self {
        case .support: .clipboard
        case .tutorial: .file
        case .email: .file
        }
    }

    var format: ImageFormat {
        switch self {
        case .email: .jpeg
        case .support, .tutorial: .png
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Système")
        case .light: String(localized: "Clair")
        case .dark: String(localized: "Sombre")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Capture (métadonnées minimales, enrichies en v1.1 avec SwiftData).

struct CapturedShot: Identifiable {
    let id: UUID
    var image: NSImage
    var date: Date
    var pinned: Bool
    var ocrText: String?
    var name: String
    var kind: ShotKind
    var fileURL: URL?
    var duration: TimeInterval

    init(
        id: UUID = UUID(),
        image: NSImage,
        date: Date = Date(),
        pinned: Bool = false,
        ocrText: String? = nil,
        name: String,
        kind: ShotKind = .image,
        fileURL: URL? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.image = image
        self.date = date
        self.pinned = pinned
        self.ocrText = ocrText
        self.name = name
        self.kind = kind
        self.fileURL = fileURL
        self.duration = duration
    }

    var pixelSize: CGSize {
        CGSize(width: round(image.size.width), height: round(image.size.height))
    }

    static func mockSet() -> [CapturedShot] {
        let calendar = Calendar.current
        let now = Date()
        func daysAgo(_ days: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return [
            CapturedShot(
                image: Images.samplePhoto(seed: 1, size: CGSize(width: 1280, height: 800)),
                date: daysAgo(0, hour: 9, minute: 12),
                pinned: true,
                ocrText: "Bonjour, voici le rapport trimestriel.",
                name: "Rapport trimestriel"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 2, size: CGSize(width: 1080, height: 720)),
                date: daysAgo(0, hour: 10, minute: 41),
                ocrText: "func captureRegion(_ rect: CGRect)",
                name: "Extrait de code"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 3, size: CGSize(width: 1440, height: 900)),
                date: daysAgo(0, hour: 14, minute: 5),
                name: "Maquette accueil"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 4, size: CGSize(width: 800, height: 800)),
                date: daysAgo(1, hour: 11, minute: 26),
                ocrText: "Facture n° 2026-041 — Total : 149,00 €",
                name: "Facture"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 5, size: CGSize(width: 1280, height: 720)),
                date: daysAgo(1, hour: 16, minute: 58),
                name: "Ticket support #4821"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 6, size: CGSize(width: 1920, height: 1080)),
                date: daysAgo(3, hour: 9, minute: 3),
                ocrText: "Étape 1 : ouvrir Réglages Système.",
                name: "Tutoriel étape 1"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 7, size: CGSize(width: 1080, height: 720)),
                date: daysAgo(5, hour: 15, minute: 44),
                name: "Palette couleurs"
            ),
            CapturedShot(
                image: Images.samplePhoto(seed: 8, size: CGSize(width: 1440, height: 900)),
                date: daysAgo(8, hour: 10, minute: 19),
                pinned: true,
                ocrText: "Objectifs T4 : annotation, OCR, historique.",
                name: "Feuille de route"
            ),
        ]
    }
}

// MARK: - Outils d'annotation (F6).

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, ellipse, line, text, highlighter
    case blur, pixelate, number, loupe, crop

    var id: String { rawValue }

    var isImplemented: Bool { true }

    var isClickTool: Bool {
        switch self {
        case .number, .text, .blur, .pixelate, .loupe: true
        case .select, .arrow, .rectangle, .ellipse, .line, .highlighter, .crop: false
        }
    }

    var isShapeTool: Bool {
        switch self {
        case .arrow, .rectangle, .ellipse, .line, .highlighter: true
        case .select, .text, .blur, .pixelate, .number, .loupe, .crop: false
        }
    }

    var title: String {
        switch self {
        case .select: String(localized: "Sélection")
        case .arrow: String(localized: "Flèche")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .line: String(localized: "Ligne")
        case .text: String(localized: "Texte")
        case .highlighter: String(localized: "Surligneur")
        case .blur: String(localized: "Flou")
        case .pixelate: String(localized: "Pixélisation")
        case .number: String(localized: "Numérotation")
        case .loupe: String(localized: "Loupe")
        case .crop: String(localized: "Recadrage")
        }
    }

    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .blur: "camera.filters"
        case .pixelate: "square.grid.3x3"
        case .number: "number.circle"
        case .loupe: "magnifyingglass.circle"
        case .crop: "crop"
        }
    }

    var keyHint: String {
        switch self {
        case .select: "V"
        case .arrow: "A"
        case .rectangle: "R"
        case .ellipse: "E"
        case .line: "L"
        case .text: "T"
        case .highlighter: "H"
        case .blur: "B"
        case .pixelate: "P"
        case .number: "N"
        case .loupe: "M"
        case .crop: "C"
        }
    }
}

// MARK: - Calque d'annotation.

enum VectorKind: String {
    case arrow, rectangle, ellipse, line, text, highlight, number

    var title: String {
        switch self {
        case .arrow: String(localized: "Flèche")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .line: String(localized: "Ligne")
        case .text: String(localized: "Texte")
        case .highlight: String(localized: "Surligneur")
        case .number: String(localized: "Numéro")
        }
    }

    var icon: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .highlight: "highlighter"
        case .number: "number.circle"
        }
    }
}

enum RasterKind: String {
    case blur, pixelate, loupe

    var title: String {
        switch self {
        case .blur: String(localized: "Flou")
        case .pixelate: String(localized: "Pixélisation")
        case .loupe: String(localized: "Loupe")
        }
    }

    var icon: String {
        switch self {
        case .blur: "camera.filters"
        case .pixelate: "square.grid.3x3"
        case .loupe: "magnifyingglass.circle"
        }
    }
}

/// Coordonnées en points image, origine en haut à gauche (comme Core Graphics / SwiftUI Canvas).
struct AnnotationLayer: Identifiable {
    let id: UUID
    var vectorKind: VectorKind?
    var rasterKind: RasterKind?
    var rasterImage: NSImage?
    var rasterParam: Double
    var start: CGPoint
    var end: CGPoint
    var text: String
    var number: Int
    var color: AnnotColor
    var lineWidth: CGFloat
    var opacity: Double
    var fontSize: CGFloat

    init(
        id: UUID = UUID(),
        vectorKind: VectorKind? = nil,
        rasterKind: RasterKind? = nil,
        rasterImage: NSImage? = nil,
        rasterParam: Double = 0,
        start: CGPoint = .zero,
        end: CGPoint = .zero,
        text: String = "",
        number: Int = 0,
        color: AnnotColor = .red,
        lineWidth: CGFloat = 4,
        opacity: Double = 1,
        fontSize: CGFloat = 28
    ) {
        self.id = id
        self.vectorKind = vectorKind
        self.rasterKind = rasterKind
        self.rasterImage = rasterImage
        self.rasterParam = rasterParam
        self.start = start
        self.end = end
        self.text = text
        self.number = number
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.fontSize = fontSize
    }

    var isRaster: Bool { rasterKind != nil }

    var listTitle: String {
        if let rasterKind { return rasterKind.title }
        if let vectorKind {
            if vectorKind == .text, !text.isEmpty { return text }
            if vectorKind == .number { return "\(vectorKind.title) \(number)" }
            return vectorKind.title
        }
        return "—"
    }

    var listIcon: String {
        if let rasterKind { return rasterKind.icon }
        return vectorKind?.icon ?? "square"
    }

    var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var bounds: CGRect {
        guard let vectorKind else { return normalizedRect }
        switch vectorKind {
        case .text:
            let size = (text as NSString).size(withAttributes: Self.textAttributes(size: fontSize))
            return CGRect(origin: start, size: CGSize(width: max(size.width, 8), height: max(size.height, 8)))
        case .number:
            let radius = fontSize * 0.85
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        case .line, .arrow, .highlight:
            return normalizedRect.insetBy(dx: -8, dy: -8)
        case .rectangle, .ellipse:
            return normalizedRect.insetBy(dx: -4, dy: -4)
        }
    }

    static func textAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]
    }
}
