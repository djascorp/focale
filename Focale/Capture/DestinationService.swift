import AppKit

// MARK: - Routage vers la destination (F3) : presse-papiers, fichier, partage.

@MainActor
enum DestinationService {
    @discardableResult
    static func route(image: CGImage, destination: Destination, settings: AppSettings) -> URL? {
        var savedURL: URL?
        if destination == .file || destination == .both {
            savedURL = save(image, settings: settings)
        }
        if destination == .clipboard || destination == .both {
            copy(image)
        }
        return savedURL
    }

    static func copy(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let data = Images.pngData(from: nsImage) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    @discardableResult
    static func save(_ image: CGImage, settings: AppSettings) -> URL? {
        let folder = URL(fileURLWithPath: settings.saveFolderPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let url = uniqueURL(in: folder, baseName: settings.sampleFileName()) else { return nil }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let data: Data?
        switch settings.saveFormat {
        case .png:
            data = rep.representation(using: .png, properties: [:])
        case .jpeg:
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
        guard let data else { return nil }
        try? data.write(to: url)
        return url
    }

    /// Nom unique : « Capture.png », « Capture 2.png », …
    static func uniqueURL(in folder: URL, baseName: String) -> URL? {
        let nsName = baseName as NSString
        let stem = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        var candidate = folder.appendingPathComponent(baseName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(index).\(ext)")
            index += 1
            if index > 1000 { return nil }
        }
        return candidate
    }

    /// Partage via un fichier temporaire (compatibilité maximale avec les services).
    static func share(_ image: CGImage, name: String, from view: NSView) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let data = Images.pngData(from: nsImage) else { return }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("png")
        try? data.write(to: temp)
        NSSharingServicePicker(items: [temp])
            .show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}
