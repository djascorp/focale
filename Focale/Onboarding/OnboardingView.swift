import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Première ouverture (§7.2.G : 3 écrans maximum).

struct OnboardingView: View {
    @Bindable var settings: AppSettings
    var onFinish: () -> Void = {}

    @State private var page: Int

    init(settings: AppSettings, startPage: Int = 0, onFinish: @escaping () -> Void = {}) {
        _settings = Bindable(wrappedValue: settings)
        _page = State(initialValue: startPage)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                valuePage.tag(0)
                permissionPage.tag(1)
                choicesPage.tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(minHeight: 380)
            footer
        }
        .frame(width: 600)
        .padding(24)
    }

    // MARK: Page 1 — valeur.

    private var valuePage: some View {
        VStack(spacing: 14) {
            LogoMark(size: 88)
            Text("Capturer, annoter, partager en moins de 3 secondes.")
                .font(.focaleDisplay)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("Un seul raccourci, une seule barre. Focale s'efface pour ne garder que l'essentiel : votre capture.")
                .font(.focaleBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 16) {
                valuePoint(icon: "rectangle.dashed", title: "Zone précise", detail: "Tailles et ratios exacts")
                valuePoint(icon: "pencil.tip", title: "Annotation", detail: "Flou, numérotation, loupe")
                valuePoint(icon: "lock.shield", title: "100 % local", detail: "Aucune image envoyée")
            }
            .padding(.top, 12)
        }
        .padding()
    }

    private func valuePoint(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(height: 28)
            Text(title).font(.focaleLabel)
            Text(detail).font(.focaleCaption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Page 2 — permission Enregistrement de l'écran.

    private var permissionPage: some View {
        PermissionPane()
            .padding()
    }

    // MARK: Page 3 — raccourci + destination.

    private var choicesPage: some View {
        VStack(spacing: 18) {
            Text("À vous de choisir")
                .font(.focaleTitle)
            Form {
                ShortcutRecorderField(label: "Raccourci Focale", shortcut: $settings.mainShortcut)
                Picker("Destination par défaut", selection: $settings.defaultDestination) {
                    ForEach(Destination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 440)
        }
        .padding()
    }

    // MARK: Pied de page.

    private var footer: some View {
        HStack {
            Button("Passer") { onFinish() }
                .buttonStyle(.link)
                .opacity(page == 2 ? 0 : 1)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == page ? Color.focaleAccentStart : .secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if page < 2 {
                Button("Continuer") {
                    withAnimation(.focaleStandard) { page += 1 }
                }
                .buttonStyle(FocaleAccentButtonStyle())
            } else {
                Button("Commencer") { onFinish() }
                    .buttonStyle(FocaleAccentButtonStyle())
            }
        }
    }
}

// MARK: - Panneau de permission (vraie API TCC).

private struct PermissionPane: View {
    @State private var granted = CGPreflightScreenCaptureAccess()
    @State private var openedSettings = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 48))
                .foregroundStyle(granted ? Color.focaleSuccess : Color.focaleAccentStart)
            Text("Autoriser la capture d'écran")
                .font(.focaleTitle)
            Text("macOS exige votre autorisation pour capturer l'écran. Focale traite tout localement : aucune image ne quitte cet appareil.")
                .font(.focaleBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if granted {
                Label("Accès accordé — merci !", systemImage: "checkmark.circle.fill")
                    .font(.focaleLabel)
                    .foregroundStyle(Color.focaleSuccess)
            } else {
                HStack(spacing: 10) {
                    Button("Autoriser…") {
                        CGRequestScreenCaptureAccess()
                        openedSettings = true
                        openPrivacySettings()
                    }
                    .buttonStyle(FocaleAccentButtonStyle())
                    Button("Vérifier à nouveau") {
                        granted = CGPreflightScreenCaptureAccess()
                    }
                }
                Text("Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran.")
                    .font(.focaleCaption)
                    .foregroundStyle(.secondary)
                if openedSettings {
                    VStack(spacing: 8) {
                        Text("macOS n'active l'autorisation qu'à la réouverture de Focale. Si la demande persiste après l'avoir accordée, relancez l'application.")
                            .font(.focaleCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                        Button("Quitter et rouvrir Focale") {
                            RelaunchHelper.relaunch()
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onReceive(poll) { _ in
            if !granted {
                granted = CGPreflightScreenCaptureAccess()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = CGPreflightScreenCaptureAccess()
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Logo (§8.8 : réticule aux angles ouverts + point lumineux).

struct LogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient.focaleAccent)
            CornerBrackets()
                .stroke(.white, lineWidth: size * 0.055)
                .frame(width: size * 0.52, height: size * 0.52)
            Circle()
                .fill(.white)
                .frame(width: size * 0.1, height: size * 0.1)
                .shadow(color: .white, radius: size * 0.06)
        }
        .frame(width: size, height: size)
        .shadow(color: .focaleAccentStart.opacity(0.45), radius: size * 0.18, y: size * 0.06)
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = rect.width * 0.32
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (.init(x: rect.minX, y: rect.minY + arm), .init(x: rect.minX, y: rect.minY), .init(x: rect.minX + arm, y: rect.minY)),
            (.init(x: rect.maxX - arm, y: rect.minY), .init(x: rect.maxX, y: rect.minY), .init(x: rect.maxX, y: rect.minY + arm)),
            (.init(x: rect.maxX, y: rect.maxY - arm), .init(x: rect.maxX, y: rect.maxY), .init(x: rect.maxX - arm, y: rect.maxY)),
            (.init(x: rect.minX + arm, y: rect.maxY), .init(x: rect.minX, y: rect.maxY), .init(x: rect.minX, y: rect.maxY - arm)),
        ]
        for (start, corner, end) in corners {
            path.move(to: start)
            path.addLine(to: corner)
            path.addLine(to: end)
        }
        return path
    }
}

#Preview("Onboarding") {
    OnboardingView(settings: AppSettings())
}
