import SwiftUI
import MacCareBattery

struct HomeBatteryCard: View {
    @ObservedObject var model: BatteryModel
    @ObservedObject var context: TrayBatteryController
    let onDetails: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var chargeSize = 36
    @ScaledMetric(relativeTo: .body) private var accessoryDiameter: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var minimumContentHeight: CGFloat = 155
    private var snapshot: BatterySnapshot? { model.snapshot }
    private var telemetry: TrayBatteryTelemetry { context.telemetry }

    var body: some View {
        Button(action: onDetails) {
            if snapshot?.present == false {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text("Ce Mac ne possède pas de batterie intégrée.")
                        .font(AppFont.body).foregroundStyle(Theme.muted)
                }
            } else {
                content.frame(maxWidth: .infinity, minHeight: minimumContentHeight, maxHeight: .infinity)
            }
        }
            .buttonStyle(HomeStatusCardButtonStyle(tint: Theme.ok))
            .foregroundStyle(Theme.fg)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Batterie")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Ouvrir la section Batterie")
            .accessibilityAction { onDetails() }
    }

    private var content: some View {
        ActivityTileLayout(alignsWithBattery: true) {
            header
            HStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) { charge; adapter }
                    VStack(alignment: .leading, spacing: 2) { charge; adapter }
                }
                Spacer(minLength: 0)
                if !context.homeAccessories.isEmpty { accessories }
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Text(source)
                    if snapshot?.onAC == false, let powerDetail {
                        Text("· " + powerDetail).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(AppFont.caption).foregroundStyle(Theme.muted)
                .help(powerDetail ?? source)
                consumer
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { title; cycles }.fixedSize()
                VStack(alignment: .leading, spacing: 2) { title; cycles }
            }
            Spacer(minLength: 2)
            Text(healthLabel).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(snapshot?.batteryFault == true ? Theme.warn : Theme.muted)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
                .help("Capacité de charge restante estimée par rapport à la capacité de conception.")
        }
    }

    private var title: some View {
        HStack(spacing: 5) {
            Image(systemName: "battery.100percent").foregroundStyle(Theme.ok).accessibilityHidden(true)
            Text("Batterie").textCase(.uppercase).tracking(0.5)
        }.font(AppFont.caption.weight(.semibold)).fixedSize()
    }

    @ViewBuilder private var cycles: some View {
        if let cycles = snapshot?.cycles {
            Text("\(cycles) \(cycles == 1 ? "cycle" : "cycles")")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize()
        }
    }

    private var charge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let percent = snapshot?.percent, (0...100).contains(percent) {
                Text(String(percent))
                Text("%").font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.muted)
            } else {
                Text("—")
            }
        }
        .font(.system(size: chargeSize, weight: .bold)).monospacedDigit().fixedSize()
        .alignmentGuide(.homeReadingBaseline) { $0[.firstTextBaseline] }
    }

    @ViewBuilder private var adapter: some View {
        if snapshot?.powerStateKnown == true, snapshot?.onAC == true, let watts = telemetry.adapterWatts {
            HStack(spacing: 2) {
                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(Theme.ok)
                Text("\(watts.formatted(.number.precision(.fractionLength(0)))) W")
            }
            .font(AppFont.caption.weight(.semibold)).foregroundStyle(Theme.muted).fixedSize()
            .help(powerDetail ?? "")
        }
    }

    private var source: String {
        if let snapshot, snapshot.present, snapshot.powerStateKnown, snapshot.onAC,
           !snapshot.charging, snapshot.percent == 100 { return "Chargée" }
        return HomeBatteryPresentation.source(snapshot)
    }

    private var accessories: some View {
        HStack(spacing: 4) {
            ForEach(context.homeAccessories) { accessory in
                HomeBatteryAccessory(accessory: accessory, diameter: accessoryDiameter)
            }
        }
        .fixedSize().transaction { $0.animation = nil }
    }

    private var consumer: some View {
        Group {
            if let consumer = telemetry.consumer {
                let application = consumer.applicationName ?? "App non identifiée"
                let label = Text(consumer.measuredPower ? "Plus énergivore" : "CPU le plus actif")
                    .foregroundStyle(Theme.muted)
                let name = Text(application).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                let value = Text(consumer.formattedValue).monospacedDigit().foregroundStyle(Theme.muted).fixedSize()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        label.fixedSize()
                        name.fixedSize()
                        Spacer(minLength: 2)
                        value
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        label
                        HStack(spacing: 4) { name; Spacer(minLength: 2); value }
                    }
                }
                .help("\(application) · \(consumer.formattedValue) · " + (consumer.measuredPower
                    ? "Puissance estimée du processus le plus énergivore."
                    : "Charge du processus le plus actif."))
            } else {
                Text(context.hasSampled ? "Consommation indisponible." : "Lecture des processus accessibles…")
                    .foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .font(AppFont.caption).frame(minHeight: 16, alignment: .leading)
        .transaction { $0.animation = nil }
    }

    private var powerDetail: String? {
        guard let snapshot, snapshot.present, snapshot.powerStateKnown else { return nil }
        if snapshot.onAC {
            if let watts = telemetry.adapterWatts { return "Chargeur \(watts.formatted(.number.precision(.fractionLength(0)))) W" }
            return context.hasSampled ? "Puissance du chargeur indisponible" : "Lecture du chargeur…"
        }
        if let remaining = HomeBatteryPresentation.remaining(snapshot) { return remaining }
        if snapshot.reliableTemperature, let temperature = snapshot.temperature {
            return "Batterie à \(temperature.formatted(.number.precision(.fractionLength(1)))) °C"
        }
        return nil
    }
    private var healthLabel: String {
        guard let snapshot, snapshot.present, let health = snapshot.healthPercent else {
            return "Santé : —"
        }
        return "\(health) % de santé"
    }
    private var accessibilitySummary: String {
        var parts = [HomeBatteryPresentation.charge(snapshot), source,
                     healthLabel,
                     "État : \(HomeBatteryPresentation.condition(snapshot))"]
        if let cycles = snapshot?.cycles { parts.append("\(cycles) \(cycles == 1 ? "cycle" : "cycles")") }
        if let powerDetail { parts.append(powerDetail) }
        parts += context.homeAccessories.map { "\($0.name) : \($0.levelDescription)" }
        if let consumer = telemetry.consumer {
            let application = consumer.applicationName ?? "App non identifiée"
            parts.append("\(consumer.measuredPower ? "Plus énergivore" : "CPU le plus actif"), \(application), \(consumer.formattedValue)")
        }
        return parts.joined(separator: ", ")
    }

}
