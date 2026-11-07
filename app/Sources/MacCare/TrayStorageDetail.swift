import SwiftUI

struct TrayStorageDetail: View {
    let space: (free: UInt64, total: UInt64)?
    let openStorage: () -> Void
    let openHealth: () -> Void
    @StateObject private var health = DiskHealthModel()
    private var usage: TrayStorageUsage? { space.flatMap { TrayStorageUsage(free: $0.free, total: $0.total) } }
    @ScaledMetric(relativeTo: .title2) private var valueSize = 24

    var body: some View {
        TrayDetailSurface(title: "Stockage interne", height: 640) {
            healthSummary
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
            Button("Voir la santé des disques", action: openHealth)
                .buttonStyle(TrayActionStyle(prominent: true))
            Button("Explorer le stockage dans MacCare", action: openStorage)
                .buttonStyle(TrayActionStyle())
        }
        .task { await health.refresh(at: "/") }
    }

    private var healthSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Santé du disque").font(.headline).accessibilityAddTraits(.isHeader)
            if health.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lecture des informations…").font(.callout)
                }
            } else if let report = health.report {
                Label(report.summary, systemImage: report.warning ? "exclamationmark.triangle" : (report.passed == true ? "checkmark.shield" : "info.circle"))
                    .font(.callout).foregroundStyle(report.warning ? Color.orange : Color.white)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { healthMetrics(report) }
                    VStack(alignment: .leading, spacing: 7) { healthMetrics(report) }
                }
                if let model = report.model { Text(model).font(.caption).foregroundStyle(TrayAppearance.secondary) }
            } else {
                Text("Données de santé indisponibles").font(.callout)
                Text("Le diagnostic complet précise les informations accessibles pour ce disque.")
                    .font(.caption).foregroundStyle(TrayAppearance.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func healthMetrics(_ report: DiskHealthReport) -> some View {
        if let value = report.temperature { Text("Température : \(value) °C").font(.caption.weight(.semibold)).monospacedDigit() }
        if let value = report.enduranceUsed { Text("Endurance consommée : \(value) %").font(.caption).monospacedDigit() }
    }
}
