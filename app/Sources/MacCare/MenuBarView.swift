import SwiftUI

/// Le volet propose des analyses et ouvre les outils ; aucune suppression automatique.
struct MenuBarView: View {
    @ObservedObject var app: AppState
    @ObservedObject var smart: SmartScanModel
    @ObservedObject var metricsStore: TrayMetricsStore
    var openMainWindowAction: (() -> Void)? = nil
    var dismissPanel: (() -> Void)? = nil
    var openSettingsAction: (() -> Void)? = nil
    var panelSize: CGSize? = nil
    var animateEntrance = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @AppStorage(TrayShortcuts.key) private var shortcuts = TrayShortcuts.defaults
    private var metrics: TrayMetrics { metricsStore.snapshot.display }
    @State private var networkReadout = TrayNetworkReadout()
    private var networkRates: TrayMetrics.WiFi? { networkReadout.wifi ?? metrics.wifi }
    @StateObject private var batteryContext = TrayBatteryController()
    @State private var showingHealth = false
    @State private var detail: TrayDetailSelection?
    @State private var disk = DiskSpace.current()
    private let hardware = MacHardwarePresentation.current
    private let machineName = Host.current().localizedName ?? MacHardwarePresentation.current.title
    private let muted = TrayAppearance.secondary
    private let highlight = TrayAppearance.accent
    private var busy: Bool { smart.stage == .scanning || smart.stage == .cleaning }
    private var bodyHeight: CGFloat {
        if let panelSize { return max(0, panelSize.height - TrayPanelLayout.footerHeight) }
        return TrayPanelLayout.frame(in: NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1512, height: 900)).height - TrayPanelLayout.footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                overview
                ScrollView { overview }
            }
            .frame(height: bodyHeight, alignment: .top)
            footer
        }
        .frame(width: panelSize?.width ?? TrayPanelLayout.width)
        .foregroundStyle(.white)
        .background(TrayBackdrop())
        .tint(highlight)
        .preferredColorScheme(.dark)
        .onAppear { networkReadout.record(metrics) }
        .onChange(of: metrics.sampledAt) { _ in networkReadout.record(metrics) }
        .popover(item: $detail, arrowEdge: .leading) { selected in
            switch selected {
            case .activity(let kind): TrayMetricDetail(kind: kind, metricsStore: metricsStore)
            case .storage: TrayStorageDetail(space: disk, openStorage: { show(.space) }, openHealth: { show(.diskHealth) })
            case .battery: TrayBatteryDetail(model: app.battery, telemetry: batteryContext.telemetry) { show(.battery) }
            }
        }
        .task(id: app.battery.snapshot?.present == true) {
            if app.battery.snapshot?.present == true { await batteryContext.monitor() }
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            entered = true
            while !Task.isCancelled {
                disk = DiskSpace.current()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.modifier(entrance(0))
            scanCard.modifier(entrance(1))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { processorCard; gpuCard }
                HStack(spacing: 6) { memoryCard; fansCard }
                HStack(spacing: 6) { storageCard; wifiCard }
            }.modifier(entrance(2))
            BatteryTrayButton(model: app.battery, telemetry: batteryContext.telemetry) { detail = .battery }.modifier(entrance(3))
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var health: MacHealthScore.Assessment {
        MacHealthScore.assess(free: disk?.free, total: disk?.total, pressure: metrics.memory?.pressure,
                              thermal: ProcessInfo.processInfo.thermalState, battery: app.battery.snapshot)
    }

    private var healthColor: Color {
        switch health.grade {
        case .excellent: return Color(hex: "#85DFBE")
        case .good: return highlight
        case .poor: return .orange
        case nil: return muted
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showingHealth = true } label: {
                HStack(spacing: 5) {
                    Text("Santé du Mac :").font(.headline)
                    Text(health.grade?.rawValue ?? "Calcul en cours").font(.headline).foregroundStyle(healthColor)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(muted).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Afficher les critères et le calcul de la santé du Mac")
            .help("Indice estimé de l’état actuel. Cliquez pour voir son calcul.")
            .popover(isPresented: $showingHealth, arrowEdge: .bottom) { MacHealthDetails(assessment: health) }
            Text(machineName).font(.callout.weight(.medium)).lineLimit(1)
                .help(hardware.title).accessibilityAddTraits(.isHeader)
            Text(specsLine)
                .font(.caption2).foregroundStyle(muted).monospacedDigit().lineLimit(1)
                .help("\(MacSystemSpecs.ram) · \(disk.map { humanSize($0.total) + " de stockage interne" } ?? "Stockage indisponible") · \(MacSystemSpecs.systemVersion) · \(MacSystemSpecs.uptime())")
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Smart Scan").font(.callout.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(scanSubtitle).font(.caption2).foregroundStyle(muted).lineLimit(1)
            }
            HStack(spacing: 12) {
                if smart.stage == .scanning {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(smart.currentLabel ?? "Analyse en cours…").font(.callout.weight(.semibold)).lineLimit(1)
                        ProgressView(value: smart.progress).accessibilityLabel("Progression du Smart Scan")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Arrêter l’analyse") { smart.cancelScan() }.buttonStyle(TrayActionStyle())
                } else if smart.stage == .cleaning {
                    Text("Nettoyage en cours…").font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Voir la progression") { show(.smartScan) }.buttonStyle(TrayActionStyle())
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(smart.lastCompletedAt == nil ? "Faites le point" : humanSize(smart.lastSafeBytes))
                            .font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1)
                        Text(smart.lastCompletedAt == nil ? "sur l’espace récupérable" : "récupérables")
                            .font(.caption2).foregroundStyle(muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: analyze) {
                        Label(smart.lastCompletedAt == nil ? "Analyser mon Mac" : "Analyser à nouveau", systemImage: "play.fill")
                    }
                    .buttonStyle(TrayActionStyle(prominent: true)).disabled(busy)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: TrayAppearance.cardRadius)
                .fill(LinearGradient(colors: [Color(hex: "#4D2B79").opacity(0.86), Color(hex: "#743AC3").opacity(0.66), Color(hex: "#302055")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: TrayAppearance.cardRadius).strokeBorder(Color(hex: "#AD82EF").opacity(0.22)))
        }
    }

    private var storageCard: some View {
        Button { detail = .storage } label: {
            TrayMetricTile(title: "Stockage interne", symbol: "internaldrive", value: disk.map { humanSize($0.free) } ?? "—") {
                if let disk { Text("libres sur \(humanSize(disk.total))").lineLimit(1) }
                else { Text("Espace indisponible") }
            } indicator: {
                if let disk { TrayStorageGrid(free: disk.free, total: disk.total) }
            }
        }
        .buttonStyle(TrayTileStyle())
        .accessibilityHint("Afficher le détail du stockage interne")
    }

    private var memoryRingFraction: Double { TrayMemoryRingLayout.rounded(metrics.memory?.fraction ?? 0) }

    private var memoryCard: some View {
        Button { detail = .activity(.memory) } label: {
            TrayMetricTile(title: "Mémoire", symbol: "memorychip", value: memoryValue) {
                Text(metrics.memory?.pressure?.title ?? "Pression indisponible").lineLimit(1)
                    .foregroundStyle(memoryPressureColor)
                    .help("Pression mémoire mesurée par macOS. Le pourcentage indique l’utilisation estimée.")
            } indicator: {
                ZStack {
                    Circle().stroke(.white.opacity(0.16), lineWidth: 3)
                    Circle().trim(from: 0, to: memoryRingFraction)
                        .stroke(AngularGradient(colors: [Color(hex: "#7442BC"), Color(hex: "#C197FF")], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }.frame(width: 28, height: 28).padding(2).accessibilityHidden(true)
            }
        }
        .buttonStyle(TrayTileStyle()).accessibilityHint("Afficher la répartition mémoire et les processus")
    }

    private var processorCard: some View {
        Button { detail = .activity(.cpu) } label: {
            TrayMetricTile(title: "Processeur", symbol: "cpu", value: cpuValue) {
                Text("Charge du processeur").lineLimit(1)
            } indicator: {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(cpuTemperature).font(.caption2.weight(.medium)).monospacedDigit()
                        .foregroundStyle(highlight)
                        .accessibilityLabel("Température du processeur : \(cpuTemperature)")
                        .help("Température maximale des capteurs CPU disponibles. Lecture en cours d’actualisation toutes les 5 secondes.")
                    TrayHistoryChart(points: metricsStore.snapshot.cpu.points, color: Color(hex: "#B481F5"))
                        .frame(width: 36, height: 12).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(TrayTileStyle()).accessibilityHint("Afficher l’historique CPU et les processus")
    }

    private var gpuCard: some View {
        TrayMetricTile(title: "GPU", symbol: "display", value: metrics.gpu?.fraction.map { "\(Int(($0 * 100).rounded())) %" } ?? "—") {
            Text(gpuStatus).lineLimit(1)
        } indicator: {
            VStack(alignment: .trailing, spacing: 3) {
                Text(metrics.gpu?.temperature.map { "\(Int($0.rounded())) °C" } ?? "— °C")
                    .font(.caption2.weight(.medium)).foregroundStyle(highlight).monospacedDigit()
                TrayHistoryChart(points: metricsStore.snapshot.gpu.points, color: highlight)
                    .frame(width: 36, height: 12).accessibilityHidden(true)
            }
        }
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: TrayAppearance.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: TrayAppearance.cardRadius).strokeBorder(.white.opacity(0.09)))
        .accessibilityElement(children: .combine)
        .help(metrics.gpu?.model ?? "Mesures du GPU indisponibles")
    }

    private var gpuStatus: String {
        guard let gpu = metrics.gpu else { return "Mesures indisponibles" }
        let activity = gpu.fraction.map { $0 < 0.01 ? "Au repos" : "Actif" } ?? "Charge indisponible"
        return activity + (gpu.cores.map { " · \($0) cœurs" } ?? "")
    }

    private var fansCard: some View {
        TrayMetricTile(title: "Ventilateurs", symbol: "fanblades", value: metrics.fans?.fastest.map { "\(Int($0.rounded())) tr/min" } ?? "—") {
            Text(metrics.fans?.state ?? "Vitesse indisponible").lineLimit(1)
        } indicator: {
            if let load = metrics.fans?.load {
                Text("\(Int((load * 100).rounded())) %").font(.caption2).monospacedDigit().foregroundStyle(muted)
                    .accessibilityLabel("Vitesse relative au maximum : \(Int((load * 100).rounded())) pour cent")
            }
        }
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: TrayAppearance.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: TrayAppearance.cardRadius).strokeBorder(.white.opacity(0.09)))
        .accessibilityElement(children: .combine)
        .help((metrics.fans?.description ?? "Lecture indisponible") + "\nGestion des ventilateurs par macOS. La valeur principale est la vitesse la plus élevée.")
    }

    private var wifiCard: some View {
        Button { detail = .activity(.wifi) } label: {
            TrayMetricTile(title: "Réseau", symbol: metrics.network?.symbol ?? "network", value: networkType) {
                VStack(alignment: .leading, spacing: 3) {
                    if let network = metrics.network, network.connected {
                        Text(network.address ?? "IP indisponible")
                            .monospacedDigit().lineLimit(1).truncationMode(.middle)
                            .help("Adresse IP locale : \(network.address ?? "indisponible") · \(network.interface)")
                            .accessibilityLabel("Adresse IP locale : \(network.address ?? "indisponible")")
                    } else { Text("Aucune liaison active").lineLimit(1) }
                    HStack(spacing: 4) {
                        Text("↓ \(NetworkRateFormat.value(networkRates?.received))").monospacedDigit()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Réception : \(NetworkRateFormat.megabits(networkRates?.received))")
                        Text("↑ \(NetworkRateFormat.value(networkRates?.sent))").monospacedDigit()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Envoi : \(NetworkRateFormat.megabits(networkRates?.sent))")
                        Text("Mb/s").accessibilityHidden(true)
                    }.lineLimit(1)
                }
            } indicator: {
                if metrics.network?.kind == .wifi {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<4) { index in
                            Capsule().fill(index < wifiSignalBars ? Color(hex: "#85DFBE") : .white.opacity(0.18))
                                .frame(width: 2, height: CGFloat(4 + index * 3))
                        }
                    }
                    .help(metrics.network?.signalDBm.map { "Signal Wi-Fi : \($0) dBm" } ?? "Signal Wi-Fi indisponible")
                    .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(TrayTileStyle()).accessibilityHint("Afficher les détails de la connexion réseau et les débits")
    }

    private var specsLine: String {
        let uptime = MacSystemSpecs.bootDate.map { MacSystemSpecs.duration(Date().timeIntervalSince($0)) } ?? "—"
        return "\(MacSystemSpecs.ram) · \(disk.map { humanSize($0.total) } ?? "—") · \(MacSystemSpecs.systemVersion) · ↑ \(uptime)"
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ForEach(TrayShortcuts.slots(shortcuts).compactMap { $0 }) { module in
                Button { show(module) } label: { Image(systemName: module.symbol).frame(width: 20) }
                    .buttonStyle(TrayActionStyle())
                    .accessibilityLabel(module.title).accessibilityInputLabels([module.title])
                    .help(module.title)
            }
            Spacer(minLength: 0)
            Button { show(.dashboard) } label: { Image(systemName: "macwindow").frame(width: 20) }
                .buttonStyle(TrayActionStyle())
                .accessibilityLabel("Ouvrir MacCare").accessibilityInputLabels(["Ouvrir MacCare"])
                .help("Ouvrir MacCare")
            if let openSettingsAction {
                Button(action: openSettingsAction) { Image(systemName: "gearshape").frame(width: 20) }
                    .buttonStyle(TrayActionStyle()).accessibilityLabel("Réglages de MacCare").help("Réglages de MacCare")
            } else if #available(macOS 14, *) {
                SettingsLink { Image(systemName: "gearshape").frame(width: 20) }.buttonStyle(TrayActionStyle())
                    .accessibilityLabel("Réglages de MacCare").help("Réglages de MacCare")
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Image(systemName: "gearshape").frame(width: 20) }
                    .buttonStyle(TrayActionStyle()).accessibilityLabel("Réglages de MacCare").help("Réglages de MacCare")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.20))
    }

    private func entrance(_ index: Int) -> TrayEntranceModifier {
        TrayEntranceModifier(index: index, enabled: animateEntrance, entered: entered, reduceMotion: reduceMotion)
    }

    private func show(_ section: Module) {
        app.openMainWindow = openMainWindowAction ?? { openWindow(id: MacCareApp.mainWindowID) }
        dismissPanel?()
        app.show(section)
    }

    private func analyze() {
        show(.smartScan)
        if !busy { smart.scan() }
    }

    private var memoryValue: String { metrics.memory.map { "\(Int($0.fraction * 100)) %" } ?? "—" }
    private var cpuValue: String { metrics.cpu.map { "\(Int($0.used * 100)) %" } ?? "—" }
    private var networkType: String {
        guard let network = metrics.network, network.connected else { return "Déconnecté" }
        return network.kind.rawValue
    }
    private var cpuTemperature: String {
        metrics.cpu?.temperature.map { "\(Int($0.rounded())) °C" } ?? "— °C"
    }
    private var memoryPressureColor: Color {
        switch metrics.memory?.pressure {
        case .normal: return Color(hex: "#85DFBE")
        case .warning: return .orange
        case .critical: return .red
        case nil: return muted
        }
    }
    private var wifiSignalBars: Int {
        guard let rssi = metrics.wifi?.signalDBm else { return 0 }
        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }
    private var scanSubtitle: String {
        if busy { return "Votre Mac fait le point" }
        guard let last = smart.lastCompletedAt else { return "Analyse seule, à votre rythme" }
        return "Dernier bilan \(Self.relative.localizedString(for: last, relativeTo: Date()))"
    }
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return formatter
    }()
}

private struct TrayBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [Color(hex: "#21103D"), Color(hex: "#160B2D"), Color(hex: "#210D3E")], startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { path in
                path.move(to: .init(x: 0, y: 135))
                path.addCurve(to: .init(x: geometry.size.width, y: 86), control1: .init(x: 280, y: 205), control2: .init(x: 350, y: 63))
                path.addLine(to: .init(x: geometry.size.width, y: geometry.size.height)); path.addLine(to: .init(x: 0, y: geometry.size.height)); path.closeSubpath()
            }
            .fill(LinearGradient(stops: [
                .init(color: Color(hex: "#8B35EC").opacity(0.68), location: 0),
                .init(color: Color(hex: "#47216B").opacity(0.22), location: 0.28),
                .init(color: .clear, location: 0.52),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom))
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
