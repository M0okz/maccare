import SwiftUI

/// Animation d’activité, sans pourcentage : le moteur ne connaît pas encore le total à lire.
struct ScanActivityRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var lineWidth: CGFloat = 3
    var color: Color = Theme.accentInk

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
                Circle().trim(from: 0.05, to: 0.72)
                    .stroke(AngularGradient(colors: [color.opacity(0.12), color], center: .center), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct StorageScanArtwork: View {
    var symbol = "internaldrive.fill"
    var color = ModuleColor.space
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.3), .clear], center: .center, startRadius: 30, endRadius: 140))
            RoundedRectangle(cornerRadius: 44)
                .fill(LinearGradient(colors: [color.shade(0.2), color.shade(-0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 44).strokeBorder(.white.opacity(0.2)))
                .frame(width: 164, height: 164).rotationEffect(.degrees(-8))
            Image(systemName: symbol).font(.system(size: 66)).foregroundStyle(.white)
            ScanActivityRing(lineWidth: 4, color: color.shade(0.6)).frame(width: 220, height: 220)
            Circle().stroke(color.shade(0.6).opacity(0.3), lineWidth: 1).frame(width: 244, height: 244)
        }.frame(width: 280, height: 260).accessibilityHidden(true)
    }
}

/// État commun des analyses. Les compteurs et l’annulation proviennent de chaque moteur.
struct AnalysisProgressView<Metrics: View>: View {
    let title: String
    let detail: String
    let symbol: String
    var color: Color = Theme.accent
    var cancelTitle = "Arrêter l’analyse"
    var cancel: (() -> Void)? = nil
    @ViewBuilder let metrics: () -> Metrics

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        StorageScanArtwork(symbol: symbol, color: color)
                            .scaleEffect(0.7).frame(height: 182)
                        Text(title).font(.system(size: 30)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        Text(detail).font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                            .lineLimit(3).truncationMode(.middle)
                        metrics().font(AppFont.body).monospacedDigit()
                    }.frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            if let cancel {
                Button(action: cancel) {
                    ZStack {
                        Circle().fill(color).frame(width: 80, height: 80)
                        ScanActivityRing(lineWidth: 4).frame(width: 92, height: 92)
                        Text("Arrêter").font(AppFont.body.weight(.semibold)).foregroundStyle(.white)
                    }.frame(width: 102, height: 102)
                }.buttonStyle(.plain).accessibilityLabel(cancelTitle)
            }
            Text("Analyse seule. Vous choisissez ensuite les éléments à traiter.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
