import SwiftUI

/// Un seul écran à la fois : les modules et leurs actions restent hors du parcours de bienvenue.
struct OnboardingView: View {
    @ObservedObject var model: PermissionsModel
    @ObservedObject var system: SystemCleanModel
    @State private var step = Step.disk
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 36

    private enum Step: Int, CaseIterable {
        case disk, automation, helper
        var title: String {
            switch self {
            case .disk: return "Accès au disque"
            case .automation: return "Éléments de démarrage"
            case .helper: return "Assistant système"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
              ScrollView {
                HStack(alignment: .center, spacing: 48) {
                    illustration
                    VStack(alignment: .leading, spacing: 22) {
                        Text(step == .disk ? "VOTRE MAC, VOTRE CONTRÔLE" : "CONFIGURATION FACULTATIVE")
                            .font(AppFont.caption.weight(.semibold)).tracking(1.4)
                            .foregroundStyle(Theme.muted)
                        content
                    }
                    .frame(maxWidth: 470, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 48).padding(.vertical, 32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
              }
            }
            footer
        }
        .foregroundStyle(Theme.fg)
        .background(Theme.window.opacity(0.65))
    }

    private var header: some View {
        HStack {
            Label("MacCare", systemImage: "checkmark.shield.fill")
                .font(AppFont.emphasis.weight(.semibold)).foregroundStyle(Theme.fg)
            Spacer()
            Text("Étape \(step.rawValue + 1) sur 3 · \(step.title)")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 16)
    }

    /// Illustration propre au projet ; décorative, sans contrôle ni information exclusive.
    private var illustration: some View {
        VStack(spacing: 24) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 36)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.surface],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(Theme.accent.opacity(0.5)))
                Image(systemName: symbol)
                    .font(.system(size: 92, weight: .light))
                    .foregroundStyle(Theme.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Image(systemName: confirmed ? "checkmark.circle.fill" : "lock.circle.fill")
                    .font(.system(size: 52))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(confirmed ? Theme.ok : Theme.accentInk, Theme.window)
                    .offset(x: 14, y: 14)
            }
            .frame(width: 230, height: 230)
            VStack(spacing: 8) {
                Text("Vous gardez la main.").font(AppFont.emphasis)
                Text("Analyse locale.\nChaque suppression reste à confirmer.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 270)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch step {
        case .disk: return "internaldrive"
        case .automation: return "gearshape.2"
        case .helper: return "shield.lefthalf.filled"
        }
    }

    private var confirmed: Bool {
        switch step {
        case .disk: return model.fullDisk == .granted
        case .automation: return model.automation == .granted
        case .helper: return system.phase == .on
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .disk: diskContent
        case .automation: automationContent
        case .helper: helperContent
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: headingSize, weight: .semibold, design: .default))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(AppFont.body).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
    }

    @ViewBuilder private var diskContent: some View {
        if model.fullDisk == .granted {
            title("L’accès au disque est prêt.")
            Label("Accès complet au disque détecté", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.ok).font(AppFont.emphasis)
            detail("MacCare peut analyser les dossiers protégés par macOS. Vous choisirez les fichiers à nettoyer avant toute suppression.")
        } else {
            title("Voyez ce qui occupe\nvotre Mac.")
            detail("L’accès complet au disque permet d’analyser les dossiers protégés, comme les caches de Safari et Mail. Sans cet accès, certaines analyses seront incomplètes.")
            VStack(alignment: .leading, spacing: 12) {
                instruction("1", "Ouvrez les réglages d’accès au disque.")
                instruction("2", "Activez MacCare dans la liste. Ajoutez l’app si elle n’y figure pas.")
                instruction("3", "Relancez MacCare si macOS le demande.")
            }
            HStack(spacing: 18) {
                Button("Afficher MacCare dans le Finder") { model.revealApp() }
                Button("Revérifier l’accès") { model.recheck() }
            }
            .buttonStyle(.link).font(AppFont.secondary)
            Button("Relancer MacCare") { model.relaunch() }
                .buttonStyle(.link).font(AppFont.secondary)
            if model.fullDisk == .unknown {
                detail("L’accès n’est pas confirmé. Vous pouvez revérifier ou continuer plus tard.")
            }
        }
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(AppFont.secondary.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.2), in: Circle())
            Text(text).font(AppFont.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var automationContent: some View {
        title(confirmed ? "Le démarrage est prêt à explorer." : "Comprenez ce qui se lance.")
        detail("L’autorisation d’Automatisation de System Events sert à lire les éléments d’ouverture de session dans le module Démarrage. Cette autorisation ne déclenche aucune modification.")
        if confirmed {
            Label("Automatisation autorisée", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.ok).font(AppFont.emphasis)
        } else {
            detail("Vous pouvez passer cette étape et l’autoriser plus tard depuis Démarrage.")
            if model.automation == .denied {
                Label("L’accès n’est pas autorisé dans macOS.", systemImage: "info.circle")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            if model.requestingAutomation {
                ProgressView("Répondez à la demande de macOS…").font(AppFont.secondary)
            }
        }
    }

    @ViewBuilder private var helperContent: some View {
        title(confirmed ? "MacCare est prêt." : "Un assistant, si vous en avez besoin.")
        detail("Trois fonctions ont besoin d’un assistant avec des droits d’administrateur : le nettoyage des journaux système, certaines tâches d’entretien et le contrôle de charge de la batterie. Il n’exécute que les opérations prévues par MacCare et ne supprime rien sans votre confirmation.")
        switch system.phase {
        case .on:
            Label("Assistant système activé", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.ok).font(AppFont.emphasis)
        case .off:
            detail("C’est facultatif. Les autres fonctions de MacCare restent disponibles sans cet assistant.")
        case .needsApproval:
            detail("L’assistant attend votre approbation dans les Réglages Système. Vous pouvez aussi terminer sans l’activer.")
            Button("J’ai approuvé : revérifier") { system.refreshStatus() }.buttonStyle(.link)
        case .unavailable:
            detail("L’assistant n’est pas disponible dans cette version de l’app. Vous pouvez utiliser les autres fonctions.")
        }
        if let message = system.statusMessage {
            Text(message).font(AppFont.secondary).foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Vos fichiers restent sur ce Mac. Lancez ensuite votre première analyse depuis l’accueil.")
            .font(AppFont.secondary).foregroundStyle(Theme.muted)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if step != .disk {
                Button("Retour") { step = step == .helper ? .automation : .disk }
                    .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
            }
            Spacer()
            if step == .helper {
                if system.phase == .off {
                    Button("Activer l’assistant…") { system.enable() }
                        .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
                } else if system.phase == .needsApproval {
                    Button("Ouvrir les Réglages") { system.openApproval() }
                        .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
                }
                primary("Commencer") { model.completeFirstRun() }
            } else if confirmed {
                primary("Continuer") { advance() }
            } else {
                Button("Plus tard") { advance() }
                    .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                if step == .disk {
                    primary("Ouvrir les Réglages") { model.openFullDiskSettings() }
                } else {
                    primary(model.requestingAutomation ? "En attente…" : model.automation == .denied ? "Ouvrir les Réglages" : "Autoriser l’Automatisation…") {
                        if model.automation == .denied { model.openAutomationSettings() }
                        else { model.requestAutomation() }
                    }
                    .disabled(model.requestingAutomation)
                }
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 24)
        .background(Theme.window)
    }

    private func primary(_ text: String, action: @escaping () -> Void) -> some View {
        Button(text, action: action)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
    }

    private func advance() {
        step = step == .disk ? .automation : .helper
    }
}
