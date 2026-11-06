import SwiftUI

struct HomeStatusCards: View {
    let app: AppState
    let availableWidth: CGFloat
    let storage: TrayStorageUsage?
    @State private var consumerID = UUID()
    var body: some View {
        VStack(spacing: 0) {
            if availableWidth >= 800 {
                HStack(alignment: .top, spacing: 18) {
                    battery.frame(width: (availableWidth - 18) * 0.44)
                    activity.frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 18) { battery; activity }
            }
        }
        .modifier(TrayMetricsConsumerModifier(store: app.trayMetrics, consumer: .dashboard(consumerID)))
    }
    private var battery: some View { HomeBatteryCard(model: app.battery) { app.select(.battery) } }
    private var activity: some View {
        HomeActivityCard(store: app.trayMetrics, storage: storage) { app.select(.space) }
    }
}

struct HomeStatusCardStyle: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content.padding(22).frame(maxWidth: .infinity, minHeight: 256, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [tint.opacity(0.13), Color(hex: "#2B2045")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
    }
}
