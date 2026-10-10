import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - Génération d'images de démonstration + traitements raster (flou, pixellisation, loupe).

enum Images {
    private static let ciContext = CIContext()

    // MARK: Images fictives pour la galerie UI.

    static func sampleDesktop(size: CGSize = CGSize(width: 1600, height: 1000)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        let wallpaper = NSGradient(
            starting: NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.55, alpha: 1),
            ending: NSColor(calibratedRed: 0.35, green: 0.18, blue: 0.62, alpha: 1)
        )
        wallpaper?.draw(in: CGRect(origin: .zero, size: size), angle: 45)

        // Fausses fenêtres pour donner du relief à l'overlay de sélection.
        drawFakeWindow(in: ctx, rect: CGRect(x: size.width * 0.12, y: size.height * 0.22, width: 560, height: 380))
        drawFakeWindow(in: ctx, rect: CGRect(x: size.width * 0.52, y: size.height * 0.34, width: 480, height: 320))

        // Barre des menus factice.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: 0, y: size.height - 28, width: size.width, height: 28))
        return image
    }

    private static func drawFakeWindow(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 0.95).cgColor)
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        // Barre de titre.
        ctx.setFillColor(NSColor(calibratedWhite: 0.88, alpha: 1).cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 34, width: rect.width, height: 34))
        // Pastilles.
        for (index, color) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.minX + 12 + CGFloat(index) * 20, y: rect.maxY - 26, width: 12, height: 12))
        }
        // Lignes de texte factices.
        ctx.setFillColor(NSColor(calibratedWhite: 0.78, alpha: 1).cgColor)
        for row in 0..<6 {
            let width = rect.width * (0.55 + Double((row * 37) % 30) / 100.0)
            ctx.fill(CGRect(x: rect.minX + 24, y: rect.minY + 24 + CGFloat(row) * 28, width: width, height: 10))
        }
    }

    static func samplePhoto(seed: Int, size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        let hues = [0.58, 0.08, 0.33, 0.75, 0.0, 0.5, 0.13, 0.65]
        let hue = hues[seed % hues.count]
        let gradient = NSGradient(
            starting: NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.9, alpha: 1),
            ending: NSColor(calibratedHue: fmod(hue + 0.18, 1.0), saturation: 0.7, brightness: 0.55, alpha: 1)
        )
        gradient?.draw(in: CGRect(origin: .zero, size: size), angle: CGFloat(30 + seed * 17))
        // Formes décoratives déterministes.
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        for index in 0..<4 {
            let side = size.width * (0.08 + Double((seed + index * 13) % 10) / 60.0)
            let point = CGPoint(
                x: Double((seed * 211 + index * 97) % 100) / 100.0 * (size.width - side),
                y: Double((seed * 137 + index * 61) % 100) / 100.0 * (size.height - side)
            )
            if (seed + index) % 2 == 0 {
                ctx.fillEllipse(in: CGRect(origin: point, size: CGSize(width: side, height: side)))
            } else {
                ctx.fill(CGRect(origin: point, size: CGSize(width: side, height: side * 0.62)))
            }
        }
        // Titre discret.
        let title = "Focale \(1000 + seed * 137)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        (title as NSString).draw(at: CGPoint(x: 28, y: 30), withAttributes: attributes)
        return image
    }

    // MARK: Export.

    static func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Encodage export selon le format (PNG sans perte, JPEG léger).
    static func encoded(_ image: NSImage, format: ImageFormat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
    }

    static func itemProvider(for image: NSImage, name: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        if let data = pngData(from: image) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    // MARK: Traitements raster (coordonnées image, origine haut-gauche).

    /// Recadre une CGImage (origine bas-gauche) à partir d'un rect en coordonnées image (origine haut-gauche).
    static func cropToImageRect(_ cgImage: CGImage, rect: CGRect) -> CGImage? {
        let height = CGFloat(cgImage.height)
        let flipped = Geometry.flipY(rect: rect, containerHeight: height)
        let integral = flipped.integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard !integral.isNull, integral.width >= 1, integral.height >= 1 else { return nil }
        return cgImage.cropping(to: integral)
    }

    static func blurred(image: NSImage, rect: CGRect, radius: Double) -> NSImage? {
        applyToCrop(of: image, rect: rect) { input in
            let clamped = input.clampedToExtent()
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = clamped
            filter.radius = Float(radius)
            return filter.outputImage?.cropped(to: input.extent)
        }
    }

    static func pixelated(image: NSImage, rect: CGRect, scale: Double) -> NSImage? {
        applyToCrop(of: image, rect: rect) { input in
            let filter = CIFilter.pixellate()
            filter.inputImage = input
            filter.scale = Float(max(scale, 2))
            filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
            return filter.outputImage?.cropped(to: input.extent)
        }
    }

    /// Composited'une loupe : disque agrandi cerclé, fond transparent hors disque.
    static func loupe(image: NSImage, center: CGPoint, radius: CGFloat, zoom: CGFloat) -> NSImage? {
        guard radius >= 8, let base = cgImage(from: image) else { return nil }
        let pointScale = CGFloat(base.width) / max(image.size.width, 1)
        let cropSide = radius * 2 / max(zoom, 1)
        let cropRect = CGRect(x: center.x - cropSide / 2, y: center.y - cropSide / 2, width: cropSide, height: cropSide)
        guard let crop = cropToImageRect(base, rect: cropRect) else { return nil }
        let side = Int((radius * 2 * pointScale).rounded())
        guard side > 0,
              let ctx = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.saveGState()
        ctx.addEllipse(in: bounds.insetBy(dx: 2, dy: 2))
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: bounds)
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(max(2 * pointScale, 2))
        ctx.strokeEllipse(in: bounds.insetBy(dx: 3, dy: 3))
        guard let composed = ctx.makeImage() else { return nil }
        return NSImage(cgImage: composed, size: CGSize(width: radius * 2, height: radius * 2))
    }

    private static func applyToCrop(
        of image: NSImage, rect: CGRect, transform: (CIImage) -> CIImage?
    ) -> NSImage? {
        guard rect.width >= 2, rect.height >= 2,
              let base = cgImage(from: image),
              let crop = cropToImageRect(base, rect: rect) else { return nil }
        let input = CIImage(cgImage: crop)
        guard let output = transform(input),
              let rendered = ciContext.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: rendered, size: rect.size)
    }

    // MARK: Recadrage déterministe (CGImage et points partagent l'origine haut-gauche : pas d'inversion).

    /// Extrait un rectangle (points, origine haut-gauche) d'une image plein écran.
    static func crop(_ image: CGImage, toPoints rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixels = CGRect(
            x: (rect.minX * scale).rounded(),
            y: (rect.minY * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let final = pixels.integral.intersection(bounds)
        guard !final.isNull, final.width >= 1, final.height >= 1 else { return nil }
        return image.cropping(to: final)
    }
}
