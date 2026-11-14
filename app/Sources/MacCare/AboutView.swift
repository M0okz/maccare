import AppKit
import SwiftUI

/// Identité du projet et point d’entrée permanent des mises à jour de MacCare.
struct AboutView: View {
    @ObservedObject var updater: AppUpdater

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Développement"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                identity
                updateCard
                projectLinks
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.top, 64)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text(AppBuildIdentity.name)
                .font(AppFont.pageTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(version)")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                .textSelection(.enabled)
            Text("Un Mac plus propre, plus fluide, sous votre contrôle.")
                .font(AppFont.body).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).padding(.top, 8)
        }
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: updater.availableVersion == nil ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                    .font(.title2).foregroundStyle(Theme.accentInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mises à jour").font(AppFont.section).accessibilityAddTraits(.isHeader)
                    Text(updateStatus).font(AppFont.secondary).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let version = updater.availableVersion {
                if let notes = updater.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   notes.range(of: "<[A-Za-z/][^>]*>", options: .regularExpression) == nil {
                    AboutReleaseNotesView(notes: notes)
                } else {
                    Text("Consultez les nouveautés de MacCare \(version) sur la page des versions.")
                        .font(AppFont.body).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link("Voir les notes de version", destination: URL(string: "https://github.com/M0okz/maccare/releases")!)
                    .font(AppFont.secondary).foregroundStyle(Theme.accentInk)
            }
            VStack(alignment: .leading, spacing: 10) {
                Button(updater.availableVersion == nil ? "Rechercher les mises à jour…" : "Télécharger la mise à jour…",
                       systemImage: updater.availableVersion == nil ? "arrow.clockwise" : "arrow.down.circle",
                       action: updater.checkForUpdates)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!updater.canCheckForUpdates)
                    .accessibilityHint(updater.availableVersion == nil ? "Rechercher une nouvelle version de MacCare" : "Ouvrir les options de téléchargement et d’installation")
                if updater.availableVersion != nil {
                    Text("Vous choisissez quand installer la nouvelle version.")
                        .font(AppFont.caption).foregroundStyle(Theme.muted)
                }
                if let date = updater.lastCheckDate {
                    Text("Dernière recherche : \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppFont.caption).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var updateStatus: String {
        if let reason = updater.unavailableReason { return reason }
        if let version = updater.availableVersion { return "MacCare \(version) est disponible." }
        if !updater.canCheckForUpdates { return "Recherche ou mise à jour en cours…" }
        return "Recherchez une nouvelle version de MacCare et ses nouveautés."
    }

    private var projectLinks: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { links }
                VStack(spacing: 12) { links }
            }
            .font(AppFont.secondary).foregroundStyle(Theme.accentInk)
            Text("Créé par Grégory NARCIN · Licence MIT")
                .font(AppFont.caption).foregroundStyle(Theme.faint)
        }
    }

    @ViewBuilder private var links: some View {
        Link("Site du projet", destination: URL(string: "https://maccare.homeblack.fr/")!)
        Link("Documentation", destination: URL(string: "https://maccare.homeblack.fr/documentation/")!)
        Link("Code source", destination: URL(string: "https://github.com/M0okz/maccare")!)
    }
}
