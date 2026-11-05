import SwiftUI

struct HomeActivityDetailView: View {
    let kind: TrayMetricDetail.Kind
    @ObservedObject var store: TrayMetricsStore
    @Environment(\.dismiss) private var dismiss
    @State private var consumerID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            TrayMetricDetail(kind: kind, metricsStore: store, height: 540)
            Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
                .buttonStyle(SecondaryActionButtonStyle()).padding(14)
        }.frame(width: 420).background(Theme.window).preferredColorScheme(.dark)
            .modifier(TrayMetricsConsumerModifier(store: store, consumer: .activityDetail(consumerID)))
    }
}
