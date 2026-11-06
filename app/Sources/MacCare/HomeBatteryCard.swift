import AppKit
import SwiftUI
import MacCareBattery

struct HomeBatteryCard: View {
    @ObservedObject var model: BatteryModel
    let onDetails: () -> Void
    @StateObject private var context = TrayBatteryController()
    @State private var windowVisible = false
    @ScaledMetric(relativeTo: .largeTitle) private var chargeSize = 36
    @ScaledMetric(relativeTo: .body) private var accessoryDiameter: CGFloat = 40
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "battery.100percent").foregroundStyle(Theme.ok).accessibilityHidden(true)
                Text("Batterie").font(.headline)
                Spacer(minLength: 4)
                Text(HomeBatteryPresentation.condition(snapshot))
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(snapshot?.batteryFault == true ? Theme.warn : Theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
            if snapshot?.present == false {
                Text("Ce Mac ne possède pas de batterie intégrée.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
            } else {
                Spacer(minLength: 0)
                charge
                Spacer(minLength: 0)
                Divider().overlay(.white.opacity(0.08))
                consumer
            }
        }
    }

    private var charge: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                chargeSummary.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                accessories
            }
            VStack(alignment: .leading, spacing: 14) {
                chargeSummary
                accessories
            }
        }
    }

    private var chargeSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(HomeBatteryPresentation.charge(snapshot))
                .font(.system(size: chargeSize, weight: .semibold)).monospacedDigit()
            Text(HomeBatteryPresentation.source(snapshot)).font(AppFont.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let powerDetail {
                Label { Text(powerDetail) } icon: {
                    Image(systemName: powerSymbol).accessibilityHidden(true)
                }.font(AppFont.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessories: some View {
        HStack(spacing: 10) {
            TrayBatteryGauge(name: "Ce Mac", symbol: "laptopcomputer", percent: snapshot?.percent,
                             diameter: accessoryDiameter, lineWidth: 3)
            ForEach(0..<2, id: \.self) { index in
                if index < telemetry.accessories.count {
                    HomeBatteryAccessory(accessory: telemetry.accessories[index])
                } else {
                    Color.clear.frame(width: accessoryDiameter + 4, height: accessoryDiameter + 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: (accessoryDiameter + 4) * 3 + 20, height: accessoryDiameter + 4)
        .transaction { $0.animation = nil }
    }

    private var consumer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let consumer = telemetry.consumer {
                Label {
                    Text(consumer.measuredPower ? "Processus le plus énergivore" : "Processus le plus actif CPU")
                } icon: {
                    Image(systemName: consumer.measuredPower ? "flame" : "cpu").accessibilityHidden(true)
                }.font(AppFont.caption).foregroundStyle(Theme.muted)
                HStack(spacing: 9) {
                    if let path = consumer.appBundlePath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true)
                    }
                    Text(consumer.name).font(AppFont.body.weight(.semibold)).lineLimit(1)
                        .truncationMode(.middle).help(consumer.name)
                    Spacer(minLength: 4)
                    Text(consumer.formattedValue).font(AppFont.emphasis).monospacedDigit().fixedSize()
                }.frame(minHeight: 26)
                .help(consumer.measuredPower ? "Estimation parmi les processus accessibles, pas la consommation totale de l’app." : "Puissance indisponible : repli sur la charge CPU, 100 % correspondant à un cœur.")
            } else {
                Label("Processus énergivores", systemImage: "flame").font(AppFont.caption).foregroundStyle(Theme.muted)
                Text(context.hasSampled ? "Consommation indisponible." : "Lecture des processus accessibles…")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
        }
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
    private var accessibilitySummary: String {
        var parts = [HomeBatteryPresentation.charge(snapshot), HomeBatteryPresentation.source(snapshot),
                     "État : \(HomeBatteryPresentation.condition(snapshot))"]
        if let powerDetail { parts.append(powerDetail) }
        parts += telemetry.accessories.prefix(2).map { "\($0.name) : dernier niveau connu \($0.percent) %" }
        if let consumer = telemetry.consumer {
            parts.append("\(consumer.measuredPower ? "Processus le plus énergivore" : "Processus le plus actif CPU") : \(consumer.name), \(consumer.formattedValue)")
        }
        return parts.joined(separator: ", ")
    }

}
