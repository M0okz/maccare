import SwiftUI

struct TrayHistoryRangePicker: View {
    @Binding var duration: TimeInterval

    var body: some View {
        Picker("Historique", selection: $duration) {
            Text("10 min").tag(TimeInterval(600))
            Text("30 min").tag(TimeInterval(1800))
            Text("1 h").tag(TimeInterval(3600))
        }.pickerStyle(.segmented)
    }
}

struct TrayHistoryDetail: View {
    let points: [TrayHistoryPoint]
    let duration: TimeInterval
    var color: Color = .cyan
    var maximum: Double = 1
    var network = false

    var body: some View {
        let stats = TrayMetricHistory.statistics(points, duration: duration)
        VStack(spacing: 8) {
            TrayHistoryChart(points: points, duration: duration, color: color, maximum: maximum, filled: true)
                .frame(height: network ? 65 : 90).accessibilityHidden(true)
            HStack {
                Text("−\(Int(duration / 60)) min")
                Spacer()
                Text("Maintenant")
            }.font(.caption2).foregroundStyle(.white.opacity(0.73))
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Moy. : \(format(stats.average))").fixedSize()
                    Spacer()
                    Text("Pic : \(format(stats.peak))").fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Moy. : \(format(stats.average))")
                    Text("Pic : \(format(stats.peak))")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption2).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Historique sur \(Int(duration / 60)) minutes") // [VERIFY] confirm label matches intent
        .accessibilityValue("Moyenne : \(format(stats.average)), pic : \(format(stats.peak))")
    }

    private func format(_ value: Double?) -> String {
        if network { return NetworkRateFormat.megabits(value) }
        return value.map { "\(Int(($0 * 100).rounded())) %" } ?? "—"
    }
}
