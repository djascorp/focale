import CoreGraphics
import Foundation

// MARK: - Conversions de coordonnées et ajustements (couvert par tests unitaires).

enum Geometry {
    /// Convertit un rectangle entre l'origine AppKit (bas-gauche) et ScreenCaptureKit (haut-gauche).
    static func flipY(rect: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: containerHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Taille en pixels pour une taille en points et un facteur d'échelle.
    static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
    }

    /// Ratio simplifié (« 16:9 ») si les dimensions sont régulières, sinon nil.
    static func simplifiedRatio(_ size: CGSize) -> String? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        let divisor = gcd(width, height)
        let ratioWidth = width / divisor
        let ratioHeight = height / divisor
        guard ratioWidth <= 32, ratioHeight <= 32 else { return nil }
        return "\(ratioWidth):\(ratioHeight)"
    }

    /// Ajustement « fit » : facteur, décalage et taille ajustée dans le conteneur.
    static func aspectFit(content: CGSize, in container: CGSize) -> (scale: CGFloat, offset: CGPoint, fitted: CGSize) {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
            return (1, .zero, .zero)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let fitted = CGSize(width: content.width * scale, height: content.height * scale)
        let offset = CGPoint(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2)
        return (scale, offset, fitted)
    }

    /// Ajustement « fill » : facteur et décalage (le contenu dépasse du conteneur).
    static func aspectFill(content: CGSize, in container: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
            return (1, .zero)
        }
        let scale = max(container.width / content.width, container.height / content.height)
        let fitted = CGSize(width: content.width * scale, height: content.height * scale)
        return (scale, CGPoint(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2))
    }

    /// Point d'un repère vers un autre via facteur + décalage.
    static func convert(_ point: CGPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    /// Borne un rectangle à un conteneur en conservant sa taille autant que possible.
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var clamped = rect
        clamped.size.width = min(max(rect.width, 0), bounds.width)
        clamped.size.height = min(max(rect.height, 0), bounds.height)
        clamped.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - clamped.width)
        clamped.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - clamped.height)
        return clamped
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 { (x, y) = (y, x % y) }
        return max(x, 1)
    }
}
