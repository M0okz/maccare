import SwiftUI
import MacCareBattery

struct BatteryView: View {
    @ObservedObject var model: BatteryModel
    @State private var category: BatteryCategory?
    @State private var lastCategory: BatteryCategory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedCategory: BatteryCategory?
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var artworkSize: CGFloat = 52

    var body: some View {
        ZStack {
            overview.allowsHitTesting(category == nil).accessibilityHidden(category != nil)
            if let selected = category {
                BatteryDetailPanel(model: model, category: $category, selected: selected)
                    .transition(ManagerPanelMotion.transition(reduceMotion: reduceMotion)).zIndex(1)
            }
        }
        .clipped().disabled(model.isTerminating)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: category)
        .onChange(of: category) { value in
            if let value { lastCategory = value }
            else { focusedCategory = lastCategory }
        }
    }
    private var overview: some View {
        ZStack {
            CategoryBackground(section: .battery)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if let snapshot = model.snapshot {
                        if snapshot.present { telemetry(snapshot) }
                        else { unavailable }
                    } else {
                        ProgressView("Lecture de la batterie…").frame(maxWidth: .infinity).padding(24)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 18) {
                        ForEach(BatteryCategory.allCases) { item in
                            categoryCard(item)
                                .disabled(item != .devices && model.snapshot?.present != true)
                        }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(AppFont.secondary).foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("La capacité et l’autonomie dépendent aussi de l’âge de la batterie, de la température et de votre utilisation.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(32).frame(maxWidth: 1060, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
    }
    private var header: some View {
        HStack(spacing: 28) {
            artwork.frame(width: 112, height: 120)
            VStack(alignment: .leading, spacing: 12) {
                Text("Batterie").font(.system(size: headingSize)).accessibilityAddTraits(.isHeader)
                Text("Prenez soin de sa santé. Choisissez ce que vous souhaitez gérer.")
                    .font(.title3).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { Task { await model.refresh(force: true) } } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }.buttonStyle(SecondaryActionButtonStyle()).disabled(model.controlsBusy)
        }
    }
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Theme.ok.shade(0.22), Theme.ok.shade(-0.4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.22)))
                .frame(width: 100, height: 100).rotationEffect(.degrees(-8))
                .shadow(color: Theme.ok.opacity(0.2), radius: 18, y: 8)
            Image(systemName: "battery.100percent").font(.system(size: artworkSize)).foregroundStyle(.white)
        }.accessibilityHidden(true)
    }
    private func categoryCard(_ item: BatteryCategory) -> some View {
        Button { category = item } label: {
            VStack(alignment: .leading, spacing: 14) {
                ModuleIcon(symbol: item.symbol, color: Theme.ok, size: 48).accessibilityHidden(true)
                Text(item.title).font(AppFont.section.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle).font(AppFont.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Label(item.action, systemImage: "arrow.right").font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(Theme.ok.shade(0.45))
            }
            .frame(maxWidth: .infinity, minHeight: 208, alignment: .leading).padding(22)
            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12)))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).foregroundStyle(Theme.fg)
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.title)
            .accessibilityHint("\(item.subtitle) \(item.action).")
            .accessibilityFocused($focusedCategory, equals: item)
    }
    private func telemetry(_ snapshot: BatterySnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                charge(snapshot)
                Spacer(minLength: 0)
                metrics(snapshot)
            }
            VStack(alignment: .leading, spacing: 18) {
                charge(snapshot)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 18) {
                    metrics(snapshot)
                }
            }
        }
        .padding(22).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
    }
    private func charge(_ snapshot: BatterySnapshot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: snapshot.charging ? "battery.100.bolt" : "battery.75percent")
                .font(.title).foregroundStyle(Theme.ok).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.percent.map { "\($0) %" } ?? "Niveau indisponible")
                    .font(AppFont.metric.weight(.semibold)).monospacedDigit()
                Text(snapshot.onAC ? (snapshot.charging ? "Branché · en charge" : "Branché · charge en pause") : "Sur batterie")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
    }
    @ViewBuilder private func metrics(_ snapshot: BatterySnapshot) -> some View {
        metric("Capacité estimée", value: snapshot.healthPercent.map { "\($0) %" } ?? "Indisponible")
        metric("Cycles de charge", value: snapshot.cycles.map(String.init) ?? "Indisponibles")
        metric("Température", value: snapshot.temperature.map { "\($0.formatted(.number.precision(.fractionLength(1)))) °C" } ?? "Indisponible")
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(AppFont.section.weight(.semibold)).monospacedDigit()
            Text(title).font(AppFont.secondary).foregroundStyle(Theme.muted)
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
    }
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aucune batterie interne détectée", systemImage: "desktopcomputer")
                .font(AppFont.section.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("Le suivi des appareils Apple reste disponible. Le contrôle de charge nécessite une batterie interne compatible.")
                .foregroundStyle(Theme.muted)
        }.padding(24)
    }
}
