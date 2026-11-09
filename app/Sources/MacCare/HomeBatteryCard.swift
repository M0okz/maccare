import AppKit
import SwiftUI
import MacCareBattery

struct HomeBatteryCard: View {
    @ObservedObject var model: BatteryModel
    let onDetails: () -> Void
    @StateObject private var context = TrayBatteryController()
    @State private var windowVisible = false
    @ScaledMetric(relativeTo: .largeTitle) private var chargeSize = 36
    @ScaledMetric(relativeTo: .body) private var accessoryDiameter: CGFloat = 34
    private var snapshot: BatterySnapshot? { model.snapshot }
    private var telemetry: TrayBatteryTelemetry { context.telemetry }

    var body: some View {
        Button(action: onDetails) { content }
            .buttonStyle(HomeStatusCardButtonStyle(tint: Theme.ok))
            .foregroundStyle(Theme.fg)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Batterie")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Ouvrir la section Batterie")
            .background(WindowVisibilityObserver { windowVisible = $0 })
            .task(id: windowVisible && snapshot?.present == true) {
                if windowVisible && snapshot?.present == true { await context.monitor() }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "battery.100percent").foregroundStyle(Theme.ok).accessibilityHidden(true)
                Text("Batterie").font(.headline)
                Spacer(minLength: 4)
                Text(healthLabel)
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(snapshot?.batteryFault == true ? Theme.warn : Theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    .help("Capacité de charge restante estimée par rapport à la capacité de conception.")
            }
            if snapshot?.present == false {
                Text("Ce Mac ne possède pas de batterie intégrée.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
            } else {
                charge
                Text(snapshot?.cycles.map { "\($0) \($0 == 1 ? "cycle" : "cycles")" } ?? "Cycles : —")
                    .font(AppFont.caption).foregroundStyle(Theme.muted)
                consumer
            }
        }
    }

    private var charge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(HomeBatteryPresentation.charge(snapshot))
                    .font(.system(size: chargeSize, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 0)
                accessories
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { source; power }
                VStack(alignment: .leading, spacing: 4) { source; power }
            }
        }
    }

    private var source: some View {
        Text(HomeBatteryPresentation.source(snapshot)).font(AppFont.caption)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var power: some View {
        if let powerDetail {
            Label { Text(powerDetail) } icon: {
                Image(systemName: powerSymbol).accessibilityHidden(true)
            }.font(AppFont.caption).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var accessories: some View {
        HStack(spacing: 10) {
            ForEach(Array(telemetry.featuredAccessories.prefix(3))) { accessory in
                HomeBatteryAccessory(accessory: accessory, diameter: accessoryDiameter)
            }
        }
        .frame(width: (accessoryDiameter + 4) * 3 + 20, height: accessoryDiameter + 4, alignment: .trailing)
        .transaction { $0.animation = nil }
    }

    private var consumer: some View {
        Group {
            if let consumer = telemetry.consumer {
                HStack(spacing: 9) {
                    if let path = consumer.appBundlePath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true)
                    } else {
                        Image(systemName: "app.dashed").resizable().scaledToFit()
                            .frame(width: 26, height: 26).foregroundStyle(Theme.muted).accessibilityHidden(true)
                    }
                    Text(consumer.name).font(AppFont.body).lineLimit(1)
                        .truncationMode(.middle).help(consumer.name)
                    Spacer(minLength: 4)
                    Text(consumer.formattedValue).font(AppFont.emphasis).monospacedDigit().fixedSize()
                }.frame(minHeight: 26)
                .help(consumer.measuredPower ? "Estimation parmi les processus accessibles, pas la consommation totale de l’app." : "Puissance indisponible : repli sur la charge CPU, 100 % correspondant à un cœur.")
            } else {
                Text(context.hasSampled ? "Consommation indisponible." : "Lecture des processus accessibles…")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
        }.frame(minHeight: 26, alignment: .leading)
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
    private var powerSymbol: String {
        if snapshot?.onAC == true { return "bolt.fill" }
        return HomeBatteryPresentation.remaining(snapshot) != nil ? "clock" : "thermometer"
    }
    private var healthLabel: String {
        guard let snapshot, snapshot.present, let health = snapshot.healthPercent else {
            return "Santé : —"
        }
        return "Santé : \(health) %"
    }
    private var accessibilitySummary: String {
        var parts = [HomeBatteryPresentation.charge(snapshot), HomeBatteryPresentation.source(snapshot),
                     healthLabel,
                     "État : \(HomeBatteryPresentation.condition(snapshot))"]
        if let cycles = snapshot?.cycles { parts.append("\(cycles) \(cycles == 1 ? "cycle" : "cycles")") }
        if let powerDetail { parts.append(powerDetail) }
        parts += telemetry.featuredAccessories.prefix(3).map { "\($0.name) : \($0.levelDescription)" }
        if let consumer = telemetry.consumer {
            parts.append("\(consumer.measuredPower ? "Processus le plus énergivore" : "Processus le plus actif CPU") : \(consumer.name), \(consumer.formattedValue)")
        }
        return parts.joined(separator: ", ")
    }

}
