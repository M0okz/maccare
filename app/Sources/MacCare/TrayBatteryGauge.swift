import SwiftUI

struct TrayBatteryGauge: View {
    let name: String
    let symbol: String
    let percent: Int?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 3)
            if let percent, (0...100).contains(percent) {
                Circle().trim(from: 0, to: Double(percent) / 100)
                    .stroke(Color(hex: "#85DFBE"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: symbol).font(.caption).foregroundStyle(TrayAppearance.secondary)
        }
        .frame(width: 34, height: 34).padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(percent.map { "\($0) %" } ?? "Indisponible")
        .help("\(name) · \(percent.map { "\($0) %" } ?? "Batterie indisponible")")
    }
}
