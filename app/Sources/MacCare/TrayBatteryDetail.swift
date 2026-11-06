import SwiftUI
import MacCareBattery

/// Lecture du modèle et de la télémétrie existants, sans nouvelle commande matérielle.
struct TrayBatteryDetail: View {
    @ObservedObject var model: BatteryModel
    let telemetry: TrayBatteryTelemetry
    let openBattery: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var chargeSize = 36

    var body: some View {
        TrayDetailSurface(title: "Batterie", height: 640) {
            if let snapshot = model.snapshot {
                if snapshot.present { details(snapshot) }
                else { Text("Ce Mac ne possède pas de batterie intégrée.").foregroundStyle(TrayAppearance.secondary) }
            } else {
                ProgressView("Lecture de la batterie…")
            }
            Divider().overlay(.white.opacity(0.1))
            Button("Ouvrir les réglages de la batterie", action: openBattery)
                .buttonStyle(TrayActionStyle())
        }
    }

    private func details(_ snapshot: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                TrayBatteryGauge(name: "Ce Mac", symbol: "laptopcomputer", percent: snapshot.percent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(HomeBatteryPresentation.charge(snapshot))
                        .font(.system(size: chargeSize, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(HomeBatteryPresentation.source(snapshot)).font(.callout)
                    if let remaining = HomeBatteryPresentation.remaining(snapshot) {
                        Text(remaining).font(.caption).foregroundStyle(TrayAppearance.secondary)
                    }
                }
            }
            TrayDetailRow(title: "Santé de la batterie", value: snapshot.healthPercent.map { "\($0) %" } ?? "Indisponible")
            TrayDetailRow(title: "Cycles de charge", value: snapshot.cycles.map(String.init) ?? "Indisponible")
            TrayDetailRow(title: "Température", value: snapshot.reliableTemperature ? snapshot.temperature.map { "\($0.formatted(.number.precision(.fractionLength(1)))) °C" } ?? "Indisponible" : "Indisponible")
            TrayDetailRow(title: "État signalé", value: HomeBatteryPresentation.condition(snapshot))
            if snapshot.powerStateKnown && snapshot.onAC, let watts = telemetry.adapterWatts {
                TrayDetailRow(title: "Puissance du chargeur", value: "\(watts.formatted(.number.precision(.fractionLength(0)))) W")
                Text("Puissance annoncée par l’adaptateur, distincte de la consommation instantanée du Mac.")
                    .font(.caption).foregroundStyle(TrayAppearance.secondary)
            }
            Text("La santé correspond à la capacité de charge restante estimée par rapport à la capacité de conception.")
                .font(.caption).foregroundStyle(TrayAppearance.secondary).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(.white.opacity(0.1))
            Text("Protection de la batterie").font(.headline).accessibilityAddTraits(.isHeader)
            if let error = model.error {
                Text("État de protection indisponible").font(.callout)
                Text(error).font(.caption).foregroundStyle(TrayAppearance.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if let consumer = telemetry.consumer {
                Divider().overlay(.white.opacity(0.1))
                Text(consumer.measuredPower ? "Processus le plus énergivore" : "Processus le plus actif CPU")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                TrayDetailRow(title: consumer.name, value: consumer.formattedValue)
                Text(consumer.measuredPower ? "Estimation parmi les processus accessibles, issue des compteurs d’énergie de macOS." : "Puissance indisponible : la charge CPU sert de repli. 100 % correspond à un cœur utilisé.")
                    .font(.caption).foregroundStyle(TrayAppearance.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !telemetry.accessories.isEmpty {
                Divider().overlay(.white.opacity(0.1))
                Text("Accessoires").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(telemetry.accessories) { accessory in
                    HStack(spacing: 10) {
                        TrayBatteryGauge(name: accessory.name, symbol: accessory.symbol, percent: accessory.percent)
                            .accessibilityHidden(true)
                        TrayDetailRow(title: accessory.name, value: "\(accessory.percent) %")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
