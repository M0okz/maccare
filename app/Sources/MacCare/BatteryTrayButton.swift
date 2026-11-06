import SwiftUI

struct BatteryTrayButton: View {
    @ObservedObject var model: BatteryModel
    var telemetry = TrayBatteryTelemetry()
    let open: () -> Void
    @ScaledMetric(relativeTo: .title) private var chargeSize = 26

    var body: some View {
        if let snapshot = model.snapshot, snapshot.present {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Batterie", systemImage: "battery.100percent").font(.caption.weight(.semibold))
                            .help(model.message)
                        if model.active {
                            Image(systemName: "checkmark.shield").font(.caption2).foregroundStyle(Color(hex: "#85DFBE"))
                                .accessibilityLabel("Protection de charge active")
                                .help(model.message)
                        }
                        Spacer()
                        Text(snapshot.healthPercent.map { "\($0) % de santé" } ?? "Santé indisponible")
                            .font(.caption2.weight(.medium)).foregroundStyle(TrayAppearance.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                            .help("Capacité de charge restante estimée par rapport à la capacité de conception.")
                    }
                    HStack(spacing: 10) {
                        Text(HomeBatteryPresentation.charge(snapshot))
                            .font(.system(size: chargeSize, weight: .semibold)).monospacedDigit().fixedSize()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(HomeBatteryPresentation.source(snapshot)).font(.caption.weight(.medium)).lineLimit(2)
                            if snapshot.powerStateKnown && snapshot.onAC, let watts = telemetry.adapterWatts {
                                Label("Chargeur \(watts.formatted(.number.precision(.fractionLength(0)))) W", systemImage: "bolt.fill")
                                    .font(.caption2).foregroundStyle(TrayAppearance.secondary)
                                    .help("Puissance annoncée par l’adaptateur, pas la consommation instantanée du Mac.")
                            } else if let remaining = HomeBatteryPresentation.remaining(snapshot) {
                                Text(remaining).font(.caption2).foregroundStyle(TrayAppearance.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 3) {
                            TrayBatteryGauge(name: "Ce Mac", symbol: "laptopcomputer", percent: snapshot.percent)
                            ForEach(Array(telemetry.accessories.prefix(2))) { accessory in
                                TrayBatteryGauge(name: accessory.name, symbol: accessory.symbol, percent: accessory.percent)
                            }
                        }
                    }
                    if let consumer = telemetry.consumer {
                        HStack(spacing: 5) {
                            Image(systemName: consumer.measuredPower ? "flame" : "cpu").accessibilityHidden(true)
                            Text(consumer.measuredPower ? "Plus énergivore" : "Plus actif CPU").fixedSize()
                            Text(consumer.name).lineLimit(1).truncationMode(.middle).help(consumer.name)
                            Text("· \(consumer.formattedValue)").monospacedDigit().fixedSize()
                        }
                        .font(.caption2).foregroundStyle(TrayAppearance.secondary)
                        .help(consumer.measuredPower ? "Puissance estimée à partir des compteurs d’énergie par processus accessibles de macOS." : "Repli CPU : la puissance par processus n’est pas disponible. 100 % correspond à un cœur utilisé.")
                    } else {
                        Text("Lecture des processus accessibles…").font(.caption2).foregroundStyle(TrayAppearance.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TrayTileStyle())
            .accessibilityHint("Ouvrir les détails de la batterie")
        }
    }
}
