import SwiftUI
import AppKit

struct PNGOptimizationInspector: View {
    let item: PNGOptimizationItem?
    let chooseImages: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let item {
                    Text(item.url.lastPathComponent).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    NativeFilePreview(url: item.url).frame(height: 220)
                        .accessibilityLabel("Aperçu de \(item.url.lastPathComponent)")
                    Text(item.url.path).font(AppFont.secondary).foregroundStyle(Theme.muted)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Taille de l’original", value: humanSize(item.originalSize))
                    if let result = item.result {
                        if result.output_path != nil {
                            LabeledContent("Taille de la copie", value: humanSize(result.optimized_bytes))
                            LabeledContent("Gain sur la copie", value: humanSize(result.savedBytes))
                        }
                        Label(item.status, systemImage: result.output_path == nil ? "info.circle" : "checkmark.circle")
                    } else if let error = item.error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger)
                    } else if item.processing {
                        ProgressView("Optimisation en cours…")
                    } else {
                        Text(item.status).foregroundStyle(Theme.muted)
                    }
                    Divider()
                    Text("La copie conserve l’image sans perte de qualité et ses métadonnées. L’original reste à sa place.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: "photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(FilesStyle.accent).accessibilityHidden(true)
                    Text("Des PNG plus légers, la même image").font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text("Créez des copies sans perte de qualité. Vos originaux et les métadonnées des images sont conservés.")
                        .font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Button("Choisir des images…", action: chooseImages).buttonStyle(.borderedProminent).controlSize(.large)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }
    }
}
