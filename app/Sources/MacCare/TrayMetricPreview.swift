#if DEBUG
import SwiftUI

/// Point d’entrée de QA : le vrai panneau et ses actions, dans une fenêtre inspectable.
struct TrayMetricPreview: View {
    /// Un aperçu de QA n’ouvre pas le volet : il demande lui-même les mesures.
    static let consumer = TrayMetricsStore.Consumer.dashboard(UUID())
    let kind: TrayMetricDetail.Kind
    @ObservedObject var metricsStore: TrayMetricsStore

    static var isOverviewRequested: Bool {
        Bundle.main.object(forInfoDictionaryKey: "MacCareTrayPreview") as? String == "overview" || CommandLine.arguments.contains("--preview-tray-overview")
    }

    static var requestedKind: TrayMetricDetail.Kind? {
        if let preview = Bundle.main.object(forInfoDictionaryKey: "MacCareTrayPreview") as? String {
            return preview == "memory" ? .memory : preview == "cpu" ? .cpu : preview == "wifi" ? .wifi : nil
        }
        if CommandLine.arguments.contains("--preview-tray-memory") { return .memory }
        if CommandLine.arguments.contains("--preview-tray-cpu") { return .cpu }
        if CommandLine.arguments.contains("--preview-tray-wifi") { return .wifi }
        return nil
    }

    var body: some View {
        TrayMetricDetail(kind: kind, metricsStore: metricsStore)
            .modifier(TrayMetricsConsumerModifier(store: metricsStore, consumer: Self.consumer))
    }
}
#endif
