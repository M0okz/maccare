import AppKit
import SwiftUI

/// Le panneau AppKit porte le flou et le contour ; cette vue ne dessine aucun fond.
struct StorageAlertView: View {
    let volume: SpaceVolumeUsage
    let openMacCare: () -> Void
    let snooze: (Int) -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14

    private var free: UInt64 { volume.total - min(volume.used, volume.total) }
    private var usedFraction: Double { Double(min(volume.used, volume.total)) / Double(max(1, volume.total)) }
    private var availableText: String { Self.availableText(free: free) }

    /// Reste court pour laisser au nom du volume la largeur de la ligne.
    static func availableText(free: UInt64) -> String {
        // Arrondir d'abord : l'accord suit la valeur affichée, 1,999 Go s'écrit « 2,00 Go libres ».
        let gigabytes = (Double(free) / 10_000_000).rounded() / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: gigabytes)) ?? "—"
        return "\(number) Go \(pl(Int(gigabytes), "libre"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Il n’y a presque plus d’espace disponible !")
                    .font(.system(size: titleSize, weight: .bold)).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ouvrez MacCare pour examiner les éléments inutiles et récupérer de l’espace.")
                    .font(.system(size: bodySize)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: "/"))
                        .resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text(volume.name).lineLimit(1).truncationMode(.tail).help(volume.name)
                            Spacer(minLength: 0)
                            Text(availableText).fixedSize().monospacedDigit()
                        }
                        .font(.system(size: bodySize, weight: .semibold))
                        GeometryReader { geometry in
                            Capsule().fill(.primary.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.red)
                                        .frame(width: geometry.size.width * usedFraction)
                                }
                        }.frame(height: 6).accessibilityHidden(true)
                    }
                }
                .padding(.top, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(volume.name), \(availableText)")
                .accessibilityValue("\(Int(usedFraction * 100)) % utilisés")
            }.padding(24)
            Divider()
            HStack {
                Menu("Ignorer") {
                    Button("Pendant une journée") { snooze(1) }
                    Button("Pendant une semaine") { snooze(7) }
                }.fixedSize()
                Spacer(minLength: 16)
                Button("Ouvrir MacCare", action: openMacCare)
                    .buttonStyle(StorageAlertPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .frame(width: 340)
    }
}
