import SwiftUI

struct ScreenCleaningView: View {
    @ObservedObject var controller: ScreenCleaningController
    @State private var duration = 120
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Mode nettoyage d’écran").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                        Text("Préparez votre Mac avant de nettoyer l’écran, le clavier et le trackpad.")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        HStack(spacing: 12) {
                            ModuleIcon(symbol: "display", color: .pink, size: 34).accessibilityHidden(true)
                            Text("Écran et saisies").font(AppFont.body.weight(.medium))
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        Text("Quitter : ⌘ + Échap").font(AppFont.body.weight(.semibold))
                    }.padding(20).frame(width: max(240, min(310, geometry.size.width * 0.28)))
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ModuleIcon(symbol: "display", color: .pink, size: 64).accessibilityHidden(true)
                            Text("Nettoyez votre Mac sereinement").font(AppFont.metric).accessibilityAddTraits(.isHeader)
                            Text("L’écran devient noir pour mieux voir les traces. Les frappes, clics et défilements sont interceptés pendant le nettoyage.")
                                .font(AppFont.body).foregroundStyle(Theme.muted)
                            VStack(alignment: .leading, spacing: 18) {
                                Label("Quittez le mode avec ⌘ + Échap, à tout moment.", systemImage: "keyboard")
                                Label("Retour automatique à la fin du compte à rebours.", systemImage: "timer")
                                Label("Tous les écrans connectés sont couverts.", systemImage: "display.2")
                            }.font(AppFont.body)
                            Divider()
                            Picker("Durée du nettoyage", selection: $duration) {
                                Text("30 secondes").tag(30)
                                Text("1 minute").tag(60)
                                Text("2 minutes").tag(120)
                                Text("5 minutes").tag(300)
                            }.frame(maxWidth: 350)
                            Text("Ce mode ne verrouille pas votre session. Les touches système, comme le bouton d’alimentation, restent disponibles.")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            ToolManagerFooter {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nettoyage pendant \(duration < 60 ? "30 secondes" : "\(duration / 60) \(pl(duration / 60, "minute"))")").font(AppFont.body.weight(.semibold))
                    Text("Retour automatique ou ⌘ + Échap pour quitter.").font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            } actions: {
                Button("Activer le mode nettoyage") { controller.start(seconds: duration) }
                    .buttonStyle(.borderedProminent).disabled(controller.active)
            }
        }
    }
}
