import AppKit
import SwiftUI
import MacCareBattery

struct HomeBatteryCard: View {
    @ObservedObject var model: BatteryModel
    let onDetails: () -> Void
    @StateObject private var context = TrayBatteryController()
    @State private var hovered = false
    @State private var windowVisible = false
    @ScaledMetric(relativeTo: .largeTitle) private var chargeSize = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var snapshot: BatterySnapshot? { model.snapshot }
    private var telemetry: TrayBatteryTelemetry { context.telemetry }

    var body: some View {
        Button(action: onDetails) { content }
            .buttonStyle(HomeStatusCardButtonStyle(tint: Theme.ok))
            .foregroundStyle(Theme.fg)
            .onHover { hovered = $0 }
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
                charge
                Divider().overlay(.white.opacity(0.08))
                accessories
                Divider().overlay(.white.opacity(0.08))
                consumer
            }
        }
    }

    private var charge: some View {
        HStack(spacing: 18) {
            batteryGauge
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
        }.frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
    }

    private var accessories: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appareils connectés").font(AppFont.caption).foregroundStyle(Theme.muted)
            if telemetry.accessories.isEmpty {
                Text(context.hasSampled ? "Aucun appareil avec batterie détecté." : "Lecture des appareils…")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(telemetry.accessories.prefix(2))) { HomeBatteryAccessory(accessory: $0) }
                }
            }
        }
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
                }
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
        parts += telemetry.accessories.prefix(2).map { "\($0.name) : \($0.percent) %" }
        if let consumer = telemetry.consumer {
            parts.append("\(consumer.measuredPower ? "Processus le plus énergivore" : "Processus le plus actif CPU") : \(consumer.name), \(consumer.formattedValue)")
        }
        return parts.joined(separator: ", ")
    }

    private var batteryGauge: some View {
        HStack(spacing: 3) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ok.opacity(0.65), lineWidth: 2)
                    .overlay(alignment: .leading) {
                        if let snapshot, snapshot.present, let percent = snapshot.percent, (0...100).contains(percent) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.ok.gradient)
                                .frame(width: max(0, geometry.size.width - 12) * Double(percent) / 100, height: 28)
                                .padding(.leading, 6)
                        }
                    }
            }.frame(width: 80, height: 40)
            Capsule().fill(Theme.ok.opacity(0.65)).frame(width: 3, height: 13)
        }
        .brightness(hovered ? 0.18 : 0)
        .shadow(color: Theme.ok.opacity(hovered ? 0.7 : 0), radius: 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        .accessibilityHidden(true)
    }
}
