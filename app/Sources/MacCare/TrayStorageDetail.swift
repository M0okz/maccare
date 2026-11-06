import SwiftUI

struct TrayStorageDetail: View {
    let space: (free: UInt64, total: UInt64)?
    let openStorage: () -> Void
    private var usage: TrayStorageUsage? { space.flatMap { TrayStorageUsage(free: $0.free, total: $0.total) } }
    @ScaledMetric(relativeTo: .title2) private var valueSize = 24

    var body: some View {
        TrayDetailSurface(title: "Stockage interne", height: 540) {
            if let usage {
                ZStack {
                    Circle().stroke(.white.opacity(0.13), lineWidth: 18)
                    Circle().trim(from: 0, to: usage.fraction)
                        .stroke(TrayAppearance.accent, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 5) {
                        Text(humanSize(usage.available))
                            .font(.system(size: valueSize, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("disponibles").font(.callout)
                        Text("sur \(humanSize(usage.total))").font(.caption).foregroundStyle(TrayAppearance.secondary)
                    }
                }
                .frame(width: 190, height: 190).padding(10).frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stockage interne disponible")
                .accessibilityValue("\(humanSize(usage.available)) sur \(humanSize(usage.total))")
                TrayDetailRow(title: "Utilisé", value: humanSize(usage.used))
                TrayDetailRow(title: "Disponible", value: humanSize(usage.available))
                TrayDetailRow(title: "Capacité totale", value: humanSize(usage.total))
                TrayDetailRow(title: "Occupation estimée", value: "\(usage.percent) %")
                Text("Espace disponible pour le volume système, selon macOS. Il peut inclure de l’espace purgeable. Ce relevé ne lance aucune analyse de vos fichiers.")
                    .font(.caption).foregroundStyle(TrayAppearance.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Mesure du stockage indisponible", systemImage: "internaldrive")
                    .font(.headline)
                Text("macOS n’a pas fourni de capacité exploitable pour le volume système.")
                    .font(.callout).foregroundStyle(TrayAppearance.secondary)
            }
            Divider().overlay(.white.opacity(0.1))
            Button("Explorer le stockage dans MacCare", action: openStorage)
                .buttonStyle(TrayActionStyle())
        }
    }
}
