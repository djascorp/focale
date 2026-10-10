import SwiftUI

// MARK: - Typographie Focale (§8.4 : SF Pro + SF Mono, chiffres tabulaires).

extension Font {
    static let focaleTitle = Font.system(size: 20, weight: .semibold)
    static let focaleHeadline = Font.system(size: 15, weight: .semibold)
    static let focaleLabel = Font.system(size: 13, weight: .medium)
    static let focaleBody = Font.system(size: 13, weight: .regular)
    static let focaleCaption = Font.system(size: 11, weight: .regular)
    static let focaleMono = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let focaleBadge = Font.system(size: 11, weight: .semibold, design: .monospaced)
}
