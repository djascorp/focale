import SwiftUI

// MARK: - Mouvements Focale (§8.6 : ressorts courts, 150–350 ms).

extension Animation {
    /// Apparition de la barre : ressort + montée de 12 pt.
    static let focaleBarAppear = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Changement de mode : fondu de 150 ms.
    static let focaleModeSwitch = Animation.easeInOut(duration: 0.15)
    /// Miniature : glissement avec réduction d'échelle.
    static let focaleToast = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// Standard pour panneaux et survols.
    static let focaleStandard = Animation.spring(response: 0.25, dampingFraction: 0.9)
}
