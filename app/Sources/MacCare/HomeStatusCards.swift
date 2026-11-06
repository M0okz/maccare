import SwiftUI

struct HomeStatusCards: View {
    let app: AppState
    let availableWidth: CGFloat
    let storage: TrayStorageUsage?
    @State private var consumerID = UUID()
    var body: some View {
        VStack(spacing: 0) {
            if availableWidth >= 1040 {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) { battery; health }
                        .frame(width: (availableWidth - 18) * 0.36)
                    activity.frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 18) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            battery.frame(minWidth: 350)
                            health.frame(minWidth: 300)
                        }.fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 18) { battery; health }
                    }
                    activity
                }
            }
        }
        .modifier(TrayMetricsConsumerModifier(store: app.trayMetrics, consumer: .dashboard(consumerID)))
    }
    private var battery: some View { HomeBatteryCard(model: app.battery) { app.select(.battery) } }
    private var health: some View {
        HomeHealthCard(store: app.trayMetrics, battery: app.battery, storage: storage)
    }
    private var activity: some View {
        HomeActivityCard(store: app.trayMetrics, storage: storage) { app.select(.space) }
    }
}

struct HomeStatusCardStyle: ViewModifier {
    let tint: Color
    var expandsVertically = false
    func body(content: Content) -> some View {
        content.padding(18).frame(maxWidth: .infinity,
                                  maxHeight: expandsVertically ? .infinity : nil, alignment: .topLeading)
            .background(LinearGradient(colors: [tint.opacity(0.13), Color(hex: "#2B2045")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
    }
}
