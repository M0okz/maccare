import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PNGOptimizationView: View {
    @ObservedObject var model: PNGOptimizationModel
    let onBack: () -> Void
    @State private var selectedID: URL?
    private var selectedItem: PNGOptimizationItem? { model.items.first { $0.id == selectedID } ?? model.items.first }

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire de fichiers") {
                Button(action: onBack) { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction).disabled(model.isRunning)
            } trailing: {
                Button("Choisir des images…", action: chooseImages).disabled(model.isRunning)
                    .buttonStyle(.bordered)
            }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            ManagerBrowserLayout {
                browser
            } detail: {
                PNGOptimizationInspector(item: selectedItem, chooseImages: chooseImages)
            } footer: {
                footer
            }
        }.modifier(ManagerPanelStyle(accent: FilesStyle.accent, background: Color(hex: "063D43")))
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alléger des images").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text("Choisissez une image pour consulter son aperçu et le résultat de l’optimisation.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text("Jusqu’à 100 PNG · 64 Mo et 32 mégapixels maximum par image")
                .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text("\(model.items.count) \(pl(model.items.count, "image"))").font(AppFont.secondary).monospacedDigit()
            if model.isRunning {
                ProgressView(value: Double(model.processedCount), total: Double(max(1, model.items.count))) {
                    Text("\(model.processedCount) sur \(model.items.count) images traitées")
                }.font(AppFont.secondary)
            }
            ForEach(model.items) { item in
                Button { selectedID = item.id } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.url.lastPathComponent).font(AppFont.body.weight(.medium)).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.status).font(AppFont.secondary).foregroundStyle(item.error == nil ? Theme.muted : Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(10)
                        .background(selectedItem?.id == item.id ? Theme.accent.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityAddTraits(selectedItem?.id == item.id ? .isSelected : [])
            }
        }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.isRunning ? "\(model.processedCount) sur \(model.items.count) images traitées"
                     : model.completed ? "\(model.copyCount) \(pl(model.copyCount, "copie")) créée\(model.copyCount > 1 ? "s" : "") · \(humanSize(model.savedBytes)) de moins"
                     : "Les originaux sont conservés.")
                    .font(AppFont.body.weight(.semibold)).monospacedDigit()
                Text(model.message ?? "Les copies sont enregistrées dans le dossier de votre choix. Aucun fichier existant n’est remplacé.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if model.isRunning {
                Button(model.stopRequested ? "Arrêt après cette image…" : "Arrêter après cette image") { model.requestStop() }
                    .disabled(model.stopRequested).buttonStyle(.bordered)
            } else if model.copyCount > 0 {
                Button("Afficher les copies") { NSWorkspace.shared.activateFileViewerSelecting(model.outputURLs) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Créer les copies optimisées…", action: chooseDestination)
                    .disabled(model.items.isEmpty).buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(18).background(Theme.sidebar)
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.prompt = "Choisir les images"
        panel.message = "Choisissez les PNG à alléger. Vos originaux resteront à leur place."
        if panel.runModal() == .OK {
            model.select(panel.urls)
            selectedID = model.items.first?.id
        }
    }
    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Enregistrer les copies"; panel.message = "Choisissez le dossier qui recevra les copies optimisées."
        if panel.runModal() == .OK, let directory = panel.url {
            Task { await model.createCopies(in: directory) }
        }
    }
}
