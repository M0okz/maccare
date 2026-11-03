import SwiftUI

struct HomeActivityWindow: Scene {
    let kind: TrayMetricDetail.Kind
    let store: TrayMetricsStore

    static func id(for kind: TrayMetricDetail.Kind) -> String {
        switch kind {
        case .memory: return "home-activity-memory"
        case .cpu: return "home-activity-cpu"
        case .wifi: return "home-activity-network"
        }
    }

    private var title: String {
        switch kind {
        case .memory: return "RAM — MacCare"
        case .cpu: return "CPU — MacCare"
        case .wifi: return "Réseau — MacCare"
        }
    }

    var body: some Scene {
        Window(title, id: Self.id(for: kind)) {
            HomeActivityDetailView(kind: kind, store: store)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
    }
}
