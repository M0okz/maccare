import SwiftUI

struct HomeStatusCards: View {
    let scale: CGFloat
    let app: AppState
    let availableWidth: CGFloat
    let storage: TrayStorageUsage?
    @EnvironmentObject private var batteryContext: TrayBatteryController
    @EnvironmentObject private var processes: TrayProcessController
    @State private var windowVisible = false
    @State private var consumerID = UUID()
    var body: some View {
        VStack(spacing: 16 * scale) {
            if availableWidth < 810 {
                ScrollView { metrics.displayScaledBlock(scale) }
            } else {
                metrics.displayScaledBlock(scale)
            }
            HomeProcessTable(controller: processes)
                .font(scale < 1 ? .body : AppFont.body)
        }
        .background(WindowVisibilityObserver { windowVisible = $0 })
        .task(id: windowVisible) {
            if windowVisible {
                await batteryContext.monitor(includeAccessories: { app.battery.snapshot?.present == true },
                                             onProcesses: processes.record)
            }
        }
        .modifier(TrayMetricsConsumerModifier(store: app.trayMetrics, consumer: .dashboard(consumerID)))
    }

    private var metrics: some View {
        HomeActivityCard(store: app.trayMetrics, storage: storage, availableWidth: availableWidth,
                         onStorage: { app.select(.space) }) {
            HomeHealthCard(store: app.trayMetrics, battery: app.battery, storage: storage) {
                HomeScanButton(model: app.smartScan, compact: availableWidth * scale < 1050) {
                    app.cleaningToolsVisible = false
                    app.select(.cleaning)
                }
            }
        } battery: {
            HomeBatteryCard(model: app.battery, context: batteryContext) { app.select(.battery) }
        }
    }
}

struct HomeStatusCardStyle: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity,
                                  minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [tint.opacity(0.115), .white.opacity(0.045)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.white.opacity(0.1)))
    }
}
