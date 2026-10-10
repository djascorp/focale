import Foundation

// MARK: - Politique d'affichage de l'onboarding (pure, testée).
//
// Règle 1 : l'écran de bienvenue ne s'affiche qu'avant le premier passage.
// Règle 2 : la page de permission ne se rouvre que si l'accès manque encore,
//            et se referme d'elle-même dès que macOS l'accorde (l'octroi
//            exigeant souvent une réouverture de l'app, le panneau scrute
//            l'état TCC au lieu de rester affiché).

enum OnboardingPolicy {
    /// Bienvenue au démarrage : uniquement si jamais terminée.
    static func shouldShowWelcome(hasOnboarded: Bool) -> Bool {
        !hasOnboarded
    }

    /// Avant une capture : procéder, ou rouvrir la récupération permission.
    static func captureGate(screenCaptureGranted: Bool) -> CaptureGate {
        screenCaptureGranted ? .proceed : .showRecovery(dismissWhenGranted: true)
    }
}

enum CaptureGate: Equatable {
    case proceed
    case showRecovery(dismissWhenGranted: Bool)
}
