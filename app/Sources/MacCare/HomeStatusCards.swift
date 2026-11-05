import SwiftUI

struct HomeStatusCards: View {
    let app: AppState
    let availableWidth: CGFloat
    @State private var consumerID = UUID()
    var body: some View {
        VStack(spacing: 0) {
            if availableWidth >= 800 {
                HStack(alignment: .top, spacing: 18) {
                    battery.frame(width: (availableWidth - 18) * 0.44)
                    HomeActivityCard(store: app.trayMetrics).frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 18) { battery; HomeActivityCard(store: app.trayMetrics) }
            }
        }
        .modifier(TrayMetricsConsumerModifier(store: app.trayMetrics, consumer: .dashboard(consumerID)))
    }
    private var battery: some View { HomeBatteryCard(model: app.battery) { app.select(.battery) } }
}

struct HomeStatusCardStyle: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content.padding(22).frame(maxWidth: .infinity, minHeight: 256, alignment: .topLeading)
            .background(LinearGradient(colors: [tint.opacity(0.13), Color(hex: "#2B2045")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
    }
}
