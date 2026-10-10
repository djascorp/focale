import AppKit
import CoreGraphics
import Foundation
import SwiftData
import Testing

@testable import Focale

// MARK: - Géométrie (conversions de coordonnées, ratios, ajustements).

@Suite("Géométrie")
struct GeometryTests {
    @Test("Inversion Y entre AppKit et ScreenCaptureKit")
    func flipY() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let flipped = Geometry.flipY(rect: rect, containerHeight: 200)
        #expect(flipped == CGRect(x: 10, y: 130, width: 100, height: 50))
        // Involutif : deux inversions redonnent le rectangle d'origine.
        #expect(Geometry.flipY(rect: flipped, containerHeight: 200) == rect)
    }

    @Test("Taille en pixels selon le facteur d'échelle")
    func pixelSize() {
        #expect(Geometry.pixelSize(points: CGSize(width: 100, height: 50), scale: 2) == CGSize(width: 200, height: 100))
        #expect(Geometry.pixelSize(points: CGSize(width: 33.3, height: 10), scale: 2) == CGSize(width: 67, height: 20))
    }

    @Test("Ratios simplifiés")
    func simplifiedRatio() {
        #expect(Geometry.simplifiedRatio(CGSize(width: 1920, height: 1080)) == "16:9")
        #expect(Geometry.simplifiedRatio(CGSize(width: 1080, height: 1080)) == "1:1")
        #expect(Geometry.simplifiedRatio(CGSize(width: 800, height: 600)) == "4:3")
        #expect(Geometry.simplifiedRatio(CGSize(width: 0, height: 100)) == nil)
    }

    @Test("Ajustement fit centré")
    func aspectFit() {
        let mapping = Geometry.aspectFit(content: CGSize(width: 800, height: 400), in: CGSize(width: 400, height: 400))
        #expect(mapping.scale == 0.5)
        #expect(mapping.fitted == CGSize(width: 400, height: 200))
        #expect(mapping.offset == CGPoint(x: 0, y: 100))
    }

    @Test("Ajustement fill couvrant")
    func aspectFill() {
        let mapping = Geometry.aspectFill(content: CGSize(width: 800, height: 400), in: CGSize(width: 400, height: 400))
        #expect(mapping.scale == 1)
        #expect(mapping.offset == CGPoint(x: -200, y: 0))
    }

    @Test("Borne un rectangle au conteneur")
    func clamp() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let clamped = Geometry.clamp(CGRect(x: 80, y: 80, width: 50, height: 50), to: bounds)
        #expect(clamped == CGRect(x: 50, y: 50, width: 50, height: 50))
    }
}

// MARK: - Détection de données sensibles.

@Suite("Données sensibles")
struct SensitiveDataTests {
    @Test("Détecte un e-mail")
    func email() {
        let findings = SensitiveData.findings(in: "Contact : marie.dupont@example.fr pour la suite.")
        #expect(findings.count == 1)
        #expect(findings.first?.kind == .email)
    }

    @Test("Détecte une clé API")
    func apiKey() {
        let findings = SensitiveData.findings(in: "token=sk-test-clef1234567890abcdef fin")
        #expect(findings.contains { $0.kind == .apiKey })
    }

    @Test("Valide une carte par Luhn et ignore les faux positifs")
    func card() {
        #expect(SensitiveData.findings(in: "CB 4242 4242 4242 4242").contains { $0.kind == .card })
        #expect(SensitiveData.findings(in: "aucune donnée 1234 ici").isEmpty)
    }

    @Test("Texte neutre sans détection")
    func none() {
        #expect(SensitiveData.findings(in: "Bonjour, voici le rapport trimestriel.").isEmpty)
    }
}

// MARK: - Raccourcis globaux (table Cocoa → Carbon).

@Suite("Raccourcis globaux")
struct HotKeyTests {
    @Test("Conversion des modificateurs Cocoa vers Carbon")
    func carbonModifiers() {
        #expect(HotKeyService.carbonModifiers(for: [.command, .shift]) == (256 | 512))
        #expect(HotKeyService.carbonModifiers(for: [.command, .option, .control, .shift]) == (256 | 512 | 2048 | 4096))
        #expect(HotKeyService.carbonModifiers(for: []) == 0)
    }

    @Test("Le raccourci par défaut est Cmd + Maj + 5")
    func defaultShortcut() {
        let shortcut = Shortcut.defaultMain
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
        #expect(flags.contains(.command) && flags.contains(.shift))
        #expect(!flags.contains(.option) && !flags.contains(.control))
        #expect(shortcut.characters == "5")
    }
}


// MARK: - Noms de fichiers (les dates locales insèrent des « / » interdits).

@Suite("Noms de fichiers")
struct FileNameTests {
    @Test("Séparateurs de date remplacés")
    func separators() {
        #expect(AppSettings.sanitizedFileName("Focale 11/10/2026 14:30:05") == "Focale 11-10-2026 14-30-05")
    }

    @Test("Bords nettoyés et repli si vide")
    func edges() {
        #expect(AppSettings.sanitizedFileName("  rapport. ") == "rapport")
        #expect(AppSettings.sanitizedFileName("   ") == "Capture")
    }
}

// MARK: - Recadrage déterministe (verrouille l'orientation haut-gauche).

@Suite("Recadrage déterministe")
struct CropTests {
    /// Quadrants en repère haut-gauche : rouge, vert / bleu, jaune.
    private func quadrantImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // CGContext en bas-gauche : le « haut » de l'image est à y = 4.
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 4, width: 4, height: 4))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 4, height: 4))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 4, y: 0, width: 4, height: 4))
        return context.makeImage()!
    }

    /// Pixel en coordonnées haut-gauche, via un rendu dans un tampon frais.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return (0, 0, 0) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Tampon bas-haut : la ligne du haut est la dernière.
        let offset = ((height - 1 - y) * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    /// Comparaisons tolérantes : la conversion d'espace colorimétrique décale les octets.
    private func isRed(_ pixel: (UInt8, UInt8, UInt8)) -> Bool {
        pixel.0 >= 200 && pixel.1 < 120 && pixel.2 < 120
    }

    private func isYellow(_ pixel: (UInt8, UInt8, UInt8)) -> Bool {
        pixel.0 >= 200 && pixel.1 >= 200 && pixel.2 < 120
    }

    @Test("Haut-gauche sans inversion")
    func topLeft() {
        guard let cropped = Images.crop(
            quadrantImage(), toPoints: CGRect(x: 0, y: 0, width: 4, height: 4), scale: 1
        ) else {
            Issue.record("recadrage impossible")
            return
        }
        #expect(cropped.width == 4 && cropped.height == 4)
        #expect(isRed(pixel(cropped, x: 0, y: 0)))
    }

    @Test("Bas-droite sans inversion")
    func bottomRight() {
        guard let cropped = Images.crop(
            quadrantImage(), toPoints: CGRect(x: 4, y: 4, width: 4, height: 4), scale: 1
        ) else {
            Issue.record("recadrage impossible")
            return
        }
        #expect(isYellow(pixel(cropped, x: 0, y: 0)))
    }

    @Test("Borné à l'image")
    func clamped() {
        let image = quadrantImage()
        #expect(Images.crop(image, toPoints: CGRect(x: 6, y: 6, width: 100, height: 100), scale: 1)?.width == 2)
        #expect(Images.crop(image, toPoints: CGRect(x: 50, y: 50, width: 10, height: 10), scale: 1) == nil)
    }
}

// MARK: - Historique persistant.

@Suite("Historique persistant")
@MainActor
struct HistoryStoreTests {
    @Test("Ajout, épinglage et suppression")
    func roundtrip() throws {
        let container = try ModelContainer(
            for: ShotRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HistoryStore(context: ModelContext(container))
        #expect(store.shots.isEmpty)
        let shot = CapturedShot(
            image: Images.samplePhoto(seed: 1, size: CGSize(width: 64, height: 64)),
            name: "Test"
        )
        store.add(shot)
        #expect(store.shots.count == 1)
        store.togglePin(shot.id)
        #expect(store.shots.first?.pinned == true)
        store.remove(shot.id)
        #expect(store.shots.isEmpty)
    }
}

// MARK: - Politique d'onboarding (ne jamais réafficher après accord).

@Suite("Politique d'onboarding")
struct OnboardingPolicyTests {
    @Test("La bienvenue ne s'affiche qu'avant le premier passage")
    func welcomeOnce() {
        #expect(OnboardingPolicy.shouldShowWelcome(hasOnboarded: false))
        #expect(!OnboardingPolicy.shouldShowWelcome(hasOnboarded: true))
    }

    @Test("La capture procède quand l'accès est accordé")
    func gateProceedsWhenGranted() {
        #expect(OnboardingPolicy.captureGate(screenCaptureGranted: true) == .proceed)
    }

    @Test("La récupération se referme d'elle-même à l'octroi")
    func recoveryDismissesOnGrant() {
        #expect(
            OnboardingPolicy.captureGate(screenCaptureGranted: false)
                == .showRecovery(dismissWhenGranted: true)
        )
    }
}

// MARK: - Onglets des réglages (6 onglets sélectionnables).

@Suite("Onglets des réglages")
struct SettingsTabTests {
    @Test("Six onglets stables et uniques")
    func sixUniqueTabs() {
        #expect(SettingsTab.allCases.count == 6)
        #expect(Set(SettingsTab.allCases.map(\.id)).count == 6)
        #expect(Set(SettingsTab.allCases.map(\.rawValue)).count == 6)
    }

    @Test("Chaque onglet a un titre et une icône")
    func titlesAndIcons() {
        for tab in SettingsTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }
}

// MARK: - Modèle d'édition.

@Suite("Modèle d'édition")
@MainActor
struct EditorModelTests {
    private func makeModel() -> EditorModel {
        EditorModel(baseImage: Images.samplePhoto(seed: 1, size: CGSize(width: 800, height: 600)))
    }

    @Test("Le brouillon devient un calque à la fin du tracé")
    func draftCommits() {
        let model = makeModel()
        model.tool = .arrow
        model.startDraft(at: CGPoint(x: 10, y: 10))
        model.updateDraft(to: CGPoint(x: 100, y: 80))
        model.finishDraft()
        #expect(model.layers.count == 1)
        #expect(model.layers.first?.vectorKind == .arrow)
    }

    @Test("Les micro-tracés sont ignorés")
    func tinyDraftDiscarded() {
        let model = makeModel()
        model.tool = .rectangle
        model.startDraft(at: CGPoint(x: 10, y: 10))
        model.updateDraft(to: CGPoint(x: 11, y: 11))
        model.finishDraft()
        #expect(model.layers.isEmpty)
    }

    @Test("Annuler et rétablir")
    func undoRedo() {
        let model = makeModel()
        model.tool = .number
        model.click(at: CGPoint(x: 50, y: 50))
        #expect(model.layers.count == 1)
        model.undo()
        #expect(model.layers.isEmpty)
        #expect(model.canRedo)
        model.redo()
        #expect(model.layers.count == 1)
    }

    @Test("La numérotation s'incrémente")
    func numbering() {
        let model = makeModel()
        model.tool = .number
        model.click(at: CGPoint(x: 10, y: 10))
        model.click(at: CGPoint(x: 20, y: 20))
        #expect(model.layers.map(\.number) == [1, 2])
    }

    @Test("Sélection et déplacement")
    func selectAndMove() {
        let model = makeModel()
        model.tool = .number
        model.click(at: CGPoint(x: 100, y: 100))
        model.tool = .select
        #expect(model.select(at: CGPoint(x: 100, y: 100)))
        model.beginMove()
        model.moveSelected(by: CGPoint(x: 10, y: 5))
        #expect(model.selected?.start == CGPoint(x: 110, y: 105))
        model.undo()
        #expect(model.selected == nil)
    }

    @Test("Le rendu final conserve les dimensions")
    func renderedSize() {
        let model = makeModel()
        model.tool = .text
        model.click(at: CGPoint(x: 40, y: 40))
        #expect(model.renderedImage().size == CGSize(width: 800, height: 600))
    }

    @Test("Le recadrage ajuste l'image, décale les calques et s'annule")
    func cropShiftsLayers() {
        let model = makeModel()
        model.tool = .number
        model.click(at: CGPoint(x: 400, y: 400))
        model.tool = .crop
        model.startCrop(at: CGPoint(x: 100, y: 100))
        model.updateCrop(to: CGPoint(x: 500, y: 500))
        model.finishCrop()
        #expect(model.baseSize == CGSize(width: 400, height: 400))
        #expect(model.layers.first?.start == CGPoint(x: 300, y: 300))
        model.undo()
        #expect(model.baseSize == CGSize(width: 800, height: 600))
        #expect(model.layers.first?.start == CGPoint(x: 400, y: 400))
    }
}
