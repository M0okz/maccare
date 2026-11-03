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
    private var metrics: TrayMetrics { metricsStore.snapshot.display }
    @State private var networkReadout = TrayNetworkReadout()
    private var networkRates: TrayMetrics.WiFi? { networkReadout.wifi ?? metrics.wifi }
    @State private var detail: TrayMetricDetail.Kind?
    @State private var disk = DiskSpace.current()
    private let hardware = MacHardwarePresentation.current
    private let muted = Color(red: 0.80, green: 0.74, blue: 0.91)
    private let highlight = Color(red: 0.76, green: 0.58, blue: 1)
    private var busy: Bool { smart.stage == .scanning || smart.stage == .cleaning }
    private var bodyHeight: CGFloat {
        if let panelSize { return max(0, panelSize.height - TrayPanelLayout.footerHeight) }
        return min(740, max(460, (NSScreen.main?.visibleFrame.height ?? 900) - 130))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header.modifier(entrance(0))
                    scanCard.modifier(entrance(1))
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("État de votre Mac")
                        HStack(spacing: 12) { storageCard; memoryCard }
                        HStack(spacing: 12) { processorCard; wifiCard }
                    }.modifier(entrance(2))
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Actions rapides")
                        quickActions
                    }.modifier(entrance(3))
                    BatteryTrayButton(model: app.battery) { show(.battery) }.modifier(entrance(4))
                    activity.modifier(entrance(4))
                }
                .padding(20).padding(.top, 10)
            }
            .frame(height: bodyHeight)
            footer
        }
        .frame(width: panelSize?.width ?? 540)
        .foregroundStyle(.white)
        .background(TrayBackdrop())
        .tint(highlight)
        .preferredColorScheme(.dark)
        .onAppear { networkReadout.record(metrics) }
        .onChange(of: metrics.sampledAt) { _ in networkReadout.record(metrics) }
        .popover(item: $detail, arrowEdge: .leading) { selected in
            TrayMetricDetail(kind: selected, metricsStore: metricsStore)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MACCARE").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(highlight)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(thermalWarning ? .orange : .green).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(thermalStatus).font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(.white.opacity(0.045), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            }
            Text("Votre Mac, au meilleur de sa forme").font(.system(size: 22, weight: .bold))
                .accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
            Text(Host.current().localizedName ?? hardware.title).font(.system(size: 13)).foregroundStyle(muted)
                .help(hardware.title).accessibilityLabel("\(Host.current().localizedName ?? "Mon Mac"), \(hardware.title)")
        }
    }

    private var thermalStatus: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "État thermique normal"
        case .fair: return "Charge thermique modérée"
        case .serious: return "État thermique élevé"
        case .critical: return "État thermique critique"
        @unknown default: return "État thermique indisponible"
        }
    }

    private var thermalWarning: Bool {
        ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
    }

    private var scanCard: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Scan").font(.system(size: 21, weight: .semibold))
                    Text(scanSubtitle).font(.system(size: 12)).foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if smart.stage == .scanning {
                    Text(smart.currentLabel ?? "Analyse en cours…").font(.system(size: 17, weight: .semibold))
                    ProgressView(value: smart.progress).accessibilityLabel("Progression du Smart Scan")
                    Button("Arrêter l’analyse") { smart.cancelScan() }.buttonStyle(TrayActionStyle())
                } else if smart.stage == .cleaning {
                    Text("Nettoyage en cours…").font(.system(size: 20, weight: .semibold))
                    Button("Voir la progression") { show(.smartScan) }.buttonStyle(TrayActionStyle())
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(smart.lastCompletedAt == nil ? "Faites le point" : humanSize(smart.lastSafeBytes))
                            .font(.system(size: smart.lastCompletedAt == nil ? 28 : 38, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(smart.lastCompletedAt == nil ? "sur l’espace récupérable" : "récupérables")
                            .font(.system(size: 13)).foregroundStyle(muted)
                    }
                    Button(action: analyze) {
                        Label(smart.lastCompletedAt == nil ? "Analyser mon Mac" : "Analyser à nouveau", systemImage: "play.fill")
                    }
                    .buttonStyle(TrayActionStyle(prominent: true)).disabled(busy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MacHardwareArtwork(hardware: hardware)
                .frame(width: 220, height: 162)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 6)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(hex: "#4D2B79").opacity(0.86), Color(hex: "#743AC3").opacity(0.66), Color(hex: "#302055")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color(hex: "#AD82EF").opacity(0.48)))
        }
    }

    private var storageCard: some View {
        Button { show(.space) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Label("Disque de démarrage", systemImage: "internaldrive").font(.system(size: 12, weight: .medium))
                if let disk {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(humanSize(disk.free)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("libres").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Text("sur \(humanSize(disk.total))").font(.system(size: 11)).foregroundStyle(muted)
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.20)).overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geometry.size.width * Double(disk.total - min(disk.free, disk.total)) / Double(max(disk.total, 1)))
                        }
                    }
                    .frame(height: 5).accessibilityHidden(true)
                } else { Text("Espace indisponible").font(.system(size: 16, weight: .semibold)) }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).padding(14)
        }
        .buttonStyle(TrayTileStyle())
        .accessibilityHint("Explorer le disque dans MacCare")
    }

    private var memoryCard: some View {
        Button { detail = .memory } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label("Mémoire", systemImage: "memorychip").font(.system(size: 12, weight: .medium))
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        TrayRollingValue(text: memoryValue, value: (metrics.memory?.fraction ?? 0) * 100)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .frame(minWidth: 84, alignment: .leading)
                        Text("Utilisation estimée").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 2)
                    ZStack {
                        Circle().stroke(.white.opacity(0.16), lineWidth: 6)
                        Circle().trim(from: 0, to: min(1, max(0, metrics.memory?.fraction ?? 0)))
                            .stroke(AngularGradient(colors: [Color(hex: "#7442BC"), Color(hex: "#C197FF")], center: .center), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }.frame(width: 45, height: 45).padding(3).accessibilityHidden(true)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: metrics.memory?.fraction)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).padding(14)
        }
        .buttonStyle(TrayTileStyle()).accessibilityHint("Afficher la répartition mémoire et les processus")
    }

    private var processorCard: some View {
        Button { detail = .cpu } label: {
            VStack(alignment: .leading, spacing: 9) {
                Label("Processeur", systemImage: "cpu").font(.system(size: 12, weight: .medium))
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        TrayRollingValue(text: cpuValue, value: (metrics.cpu?.used ?? 0) * 100)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .frame(minWidth: 84, alignment: .leading)
                        Text("Charge du processeur").font(.system(size: 10)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    TrayHistoryChart(points: metricsStore.snapshot.cpu.points, color: Color(hex: "#B481F5"))
                        .frame(width: 80, height: 32).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).padding(14)
        }
        .buttonStyle(TrayTileStyle()).accessibilityHint("Afficher l’historique CPU et les processus")
    }

    private var wifiCard: some View {
        Button { detail = .wifi } label: {
            VStack(alignment: .leading, spacing: 9) {
                Label("Wi-Fi", systemImage: "wifi").font(.system(size: 12, weight: .medium))
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(wifiState).font(.system(size: 23, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                        if metrics.wifi?.connected == true {
                            HStack(spacing: 4) {
                                Text("↓")
                                TrayRollingValue(text: TrayMetricDetail.speed(networkRates?.received), value: networkRates?.received ?? 0, duration: 1.2)
                                    .frame(width: 61, alignment: .leading)
                                Text("↑")
                                TrayRollingValue(text: TrayMetricDetail.speed(networkRates?.sent), value: networkRates?.sent ?? 0, duration: 1.2)
                                    .frame(width: 61, alignment: .leading)
                            }
                            .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.75)
                        } else { Text("Aucune liaison active").font(.system(size: 10)).foregroundStyle(muted) }
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<4) { index in
                            Capsule().fill(index < wifiSignalBars ? Color(hex: "#85DFBE") : .white.opacity(0.18))
                                .frame(width: 3, height: CGFloat(6 + index * 4))
                        }
                    }
                    .help(metrics.wifi?.signalDBm.map { "Signal Wi-Fi : \($0) dBm" } ?? "Signal Wi-Fi indisponible")
                    .accessibilityLabel(metrics.wifi?.signalDBm.map { "Signal Wi-Fi : \($0) dBm" } ?? "Signal Wi-Fi indisponible")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).padding(14)
        }
        .buttonStyle(TrayTileStyle()).accessibilityHint("Afficher les débits et tester la vitesse Internet")
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button { show(.cleaningOverview) } label: { Label("Libérer de l’espace", systemImage: "trash").frame(maxWidth: .infinity) }
            Button { show(.performanceOverview) } label: { Label("Optimiser", systemImage: "gauge.with.needle").frame(maxWidth: .infinity) }
            Button(action: analyze) { Label("Vérifier le système", systemImage: "checkmark.shield").frame(maxWidth: .infinity) }.disabled(busy)
            Menu {
                Button("Explorer le disque") { show(.space) }
                Button("Tous les outils") { show(.toolsOverview) }
                Button("Activité récente") { show(.dashboard) }
                Divider()
                Text(scheduleText)
                Button("Quitter MacCare") { NSApp.terminate(nil) }
            } label: { Label("Plus", systemImage: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1).minimumScaleFactor(0.85)
        .buttonStyle(TrayActionStyle())
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Activité récente")
            if !app.activity.isEmpty {
                ForEach(Array(app.activity.prefix(2))) { entry in
                    Button { show(entry.module) } label: {
                        activityRow(entry.title, date: entry.date)
                    }.buttonStyle(.borderless)
                }
            } else if let last = smart.lastCompletedAt {
                Button { show(.smartScan) } label: { activityRow("Dernier Smart Scan", date: last) }.buttonStyle(.borderless)
            } else {
                Text("Votre prochaine analyse apparaîtra ici.").font(.system(size: 12)).foregroundStyle(muted)
            }
        }
    }

    private func activityRow(_ title: String, date: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(highlight).accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(Self.relative.localizedString(for: date, relativeTo: Date())).font(.system(size: 11)).foregroundStyle(muted)
            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(muted).accessibilityHidden(true)
        }
        .padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { show(.dashboard) } label: { Label("Ouvrir MacCare", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(TrayActionStyle())
            if let openSettingsAction {
                Button(action: openSettingsAction) { Image(systemName: "gearshape") }
                    .buttonStyle(TrayActionStyle()).accessibilityLabel("Réglages de MacCare").help("Réglages de MacCare")
            } else if #available(macOS 14, *) {
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(TrayActionStyle())
                    .accessibilityLabel("Réglages de MacCare").help("Réglages de MacCare")
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Image(systemName: "gearshape") }
                    .buttonStyle(TrayActionStyle()).accessibilityLabel("Réglages de MacCare")
            }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(TrayActionStyle()).accessibilityLabel("Quitter MacCare").help("Quitter MacCare")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.black.opacity(0.20))
    }

    private func entrance(_ index: Int) -> TrayEntranceModifier {
        TrayEntranceModifier(index: index, enabled: animateEntrance, entered: entered, reduceMotion: reduceMotion)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
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
    private var wifiState: String {
        guard let wifi = metrics.wifi else { return "Indisponible" }
        return !wifi.powered ? "Désactivé" : wifi.connected ? "Connecté" : "Déconnecté"
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
    private var scheduleText: String {
        switch ScanScheduler.frequency {
        case .off: return "Analyse automatique désactivée"
        case .daily: return "Analyse automatique quotidienne"
        case .weekly: return "Analyse automatique hebdomadaire"
        }
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

private struct TrayActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, prominent ? 16 : 10).frame(minHeight: prominent ? 36 : 38)
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
            .background {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: prominent ? [Color(hex: "#AB64F4"), Color(hex: "#793BE0")] : [.white.opacity(hovered ? 0.16 : 0.10), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(prominent ? 0.25 : 0.17)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onHover { hovered = $0 }
    }
}

private struct TrayTileStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(LinearGradient(colors: [.white.opacity(hovered ? 0.13 : 0.085), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(hovered ? 0.24 : 0.14)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onHover { hovered = $0 }
    }
}
