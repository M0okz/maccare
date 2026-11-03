import SwiftUI
import MacCareBattery

struct HomeBatteryCard: View {
    @ObservedObject var model: BatteryModel
    let onDetails: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var snapshot: BatterySnapshot? { model.snapshot }

    var body: some View {
        Button(action: onDetails) {
            content
        }
        .buttonStyle(HomeStatusCardButtonStyle(tint: Theme.ok))
        .foregroundStyle(Theme.fg)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Batterie")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Ouvrir la section Batterie")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "battery.100percent").foregroundStyle(Theme.ok).accessibilityHidden(true)
                Text("Batterie").font(.headline)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(AppFont.secondary).foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            HStack(spacing: 18) {
                batteryGauge
                VStack(alignment: .leading, spacing: 5) {
                    Text(HomeBatteryPresentation.charge(snapshot)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                    Text(HomeBatteryPresentation.source(snapshot)).font(AppFont.secondary).foregroundStyle(Theme.ok)
                        .fixedSize(horizontal: false, vertical: true)
                    if let environmentDetail {
                        Text(environmentDetail).font(AppFont.caption).foregroundStyle(Theme.muted)
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            Divider().overlay(.white.opacity(0.08))
            HStack(alignment: .top, spacing: 14) {
                metric("Capacité estimée", value: capacity)
                    .help("Capacité de charge estimée par rapport à la capacité de conception, selon les relevés matériels.")
                metric("Cycles", value: cycles)
                metric("État", value: HomeBatteryPresentation.condition(snapshot))
            }
        }
    }

    private var capacity: String { snapshot?.present == true ? snapshot?.healthPercent.map { "\($0) %" } ?? "—" : "—" }
    private var cycles: String { snapshot?.present == true ? snapshot?.cycles.map(String.init) ?? "—" : "—" }
    private var environmentDetail: String? {
        if let remaining = HomeBatteryPresentation.remaining(snapshot) { return remaining }
        guard let snapshot, snapshot.reliableTemperature, let temperature = snapshot.temperature else { return nil }
        return "Batterie à \(temperature.formatted(.number.precision(.fractionLength(1)))) °C"
    }
    private var accessibilitySummary: String {
        [HomeBatteryPresentation.charge(snapshot), HomeBatteryPresentation.source(snapshot), environmentDetail,
         "Capacité estimée : \(capacity)", "Cycles : \(cycles)", "État : \(HomeBatteryPresentation.condition(snapshot))"]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.caption).foregroundStyle(Theme.muted)
            Text(value).font(AppFont.body.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
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
