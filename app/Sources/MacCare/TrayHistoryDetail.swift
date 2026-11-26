import SwiftUI

struct TrayHistoryRangePicker: View {
    @Binding var duration: TimeInterval

    var body: some View {
        Picker("Historique", selection: $duration) {
            Text("10 min").tag(TimeInterval(600))
            Text("30 min").tag(TimeInterval(1800))
            Text("1 h").tag(TimeInterval(3600))
            Text("24 h").tag(TimeInterval(86400))
            Text("7 j").tag(TimeInterval(7 * 86400))
            Text("30 j").tag(ActivityHistoryArchive.retention)
        }.actionCursor().pickerStyle(.menu)
    }
}

struct TrayHistoryDetail: View {
    let points: [TrayHistoryPoint]
    let duration: TimeInterval
    var color: Color = .cyan
    var maximum: Double = 1
    var network = false
    var end: TimeInterval?
    private var rangeLabel: String { duration >= 86400 ? "\(Int(duration / 86400)) j" : "\(Int(duration / 60)) min" }

    var body: some View {
        let stats = TrayMetricHistory.statistics(points, duration: duration, end: end)
        let averageLabel = stats.estimated ? "Moy. estimée" : "Moy."
        let date = stats.peakTime.map { timestamp in
            let date = Date(timeIntervalSince1970: timestamp)
            let endDate = Date(timeIntervalSince1970: end ?? points.last?.time ?? timestamp)
            let withDay = duration >= 86400 || !Calendar.current.isDate(date, inSameDayAs: endDate)
            return date.formatted(date: withDay ? .abbreviated : .omitted, time: .standard)
        }
        let peakDescription = date ?? "heure inconnue"
        let accessibleMean = stats.estimated ? "Moyenne estimée" : "Moyenne"
        VStack(spacing: 8) {
            TrayHistoryChart(points: points, duration: duration, color: color, maximum: maximum, filled: true, endTime: end)
                .frame(height: network ? 65 : 90).accessibilityHidden(true)
            HStack {
                Text("−\(rangeLabel)")
                Spacer()
                Text("Maintenant")
            }.font(.caption2).foregroundStyle(.white.opacity(0.73))
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(averageLabel) : \(format(stats.average))").fixedSize()
                    Spacer()
                    Text("Pic : \(format(stats.peak))").fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(averageLabel) : \(format(stats.average))")
                    Text("Pic : \(format(stats.peak))")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption2).monospacedDigit()
            if stats.peak != nil {
                Text(date ?? "Heure du pic inconnue")
                    .font(.caption2).foregroundStyle(.white.opacity(0.73)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Historique sur \(rangeLabel)")
        .accessibilityValue("\(accessibleMean) : \(format(stats.average)), pic : \(format(stats.peak))\(stats.peak == nil ? "" : ", " + peakDescription)")
    }

    private func format(_ value: Double?) -> String {
        if network { return NetworkRateFormat.megabits(value) }
        return value.map { "\(Int(($0 * 100).rounded())) %" } ?? "—"
    }
}

/// Only the selected metric and period are queried, once per successful batch.
struct ActivityTrendChart: View {
    let archive: ActivityHistoryArchive?
    let series: ActivitySeries
    let duration: TimeInterval
    let revision: Int
    var color: Color = .cyan
    var network = false

    private struct Request: Equatable {
        let series: ActivitySeries
        let duration: TimeInterval
        let revision: Int
    }
    @State private var points: [TrayHistoryPoint] = []
    @State private var end: TimeInterval = 0
    @State private var message: String?
    @State private var loaded: Request?

    var body: some View {
        let request = Request(series: series, duration: duration, revision: revision)
        VStack {
            if loaded?.series != series || loaded?.duration != duration {
                ProgressView().controlSize(.small)
            } else if let message {
                Text(message).font(.caption)
            } else {
                TrayHistoryDetail(points: points, duration: duration, color: color,
                                  maximum: network ? max(12_500, (points.map(\.peak).max() ?? 0) * 1.15) : 1,
                                  network: network, end: end)
            }
        }
        .task(id: request) {
            let now = Date().timeIntervalSince1970
            do {
                let result = try await archive?.trend(series, duration: duration, end: now) ?? []
                guard !Task.isCancelled else { return }
                points = result
                end = now
                message = result.isEmpty ? "Aucun relevé archivé sur cette période." : nil
            } catch {
                guard !Task.isCancelled else { return }
                message = "Historique local indisponible."
            }
            loaded = request
        }
    }
}
