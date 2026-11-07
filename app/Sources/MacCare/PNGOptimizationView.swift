import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PNGOptimizationView: View {
    @ObservedObject var model: PNGOptimizationModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Alléger des images") {
                Button(action: onBack) { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Choisir des images…", action: chooseImages).disabled(model.isRunning)
                    .buttonStyle(SecondaryActionButtonStyle())
            }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(FilesStyle.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.completed ? (model.copyCount > 0 ? "Vos copies sont prêtes" : "Traitement terminé") : "Des PNG plus légers, la même image")
                                .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Text("Créez des copies sans perte de qualité. Vos originaux et les métadonnées des images sont conservés.")
                                .font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if model.isRunning {
                        ProgressView(value: Double(model.processedCount), total: Double(max(1, model.items.count))) {
                            Text("\(model.processedCount) sur \(model.items.count) images traitées")
                        }
                    } else if model.completed {
                        Label("\(model.copyCount) \(pl(model.copyCount, "copie")) créée\(model.copyCount > 1 ? "s" : "") · \(humanSize(model.savedBytes)) de moins sur les copies", systemImage: model.copyCount > 0 ? "checkmark.circle" : "info.circle")
                            .font(AppFont.body.weight(.semibold)).monospacedDigit()
                    }
                    if model.items.isEmpty {
                        VStack(spacing: 14) {
                            Text("Choisissez les images PNG à alléger.").font(AppFont.body)
                            Button("Choisir des images…", action: chooseImages).buttonStyle(.borderedProminent)
                            Text("Jusqu’à 100 images · 64 Mo et 32 mégapixels maximum par image")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }.frame(maxWidth: .infinity).padding(.vertical, 54)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(model.items) { item in
                                HStack(spacing: 14) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                        .resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.url.lastPathComponent).font(AppFont.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                                        Text(item.status).font(AppFont.secondary).foregroundStyle(item.error == nil ? Theme.muted : Theme.danger)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(humanSize(item.originalSize)).font(AppFont.secondary).monospacedDigit()
                                        if let result = item.result, result.output_path != nil {
                                            Text("→ \(humanSize(result.optimized_bytes))").font(AppFont.body.weight(.semibold)).monospacedDigit()
                                        }
                                    }
                                }.padding(.vertical, 14)
                                Divider()
                            }
                        }
                    }
                    if let message = model.message { Label(message, systemImage: "info.circle").font(AppFont.secondary) }
                }.padding(28)
            }
            Divider()
            AdaptiveActionRow {
                Text("Les copies sont enregistrées dans le dossier de votre choix. Aucun fichier existant n’est remplacé.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
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
            }.padding(20)
        }.background(Theme.window).foregroundStyle(Theme.fg)
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.prompt = "Choisir les images"
        panel.message = "Choisissez les PNG à alléger. Vos originaux resteront à leur place."
        if panel.runModal() == .OK { model.select(panel.urls) }
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
