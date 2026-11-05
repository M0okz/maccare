import SwiftUI
import Charts
import MacCareBattery

struct BatteryHistoryView: View {
    @ObservedObject var model: BatteryModel
    @State private var days = 7
    private var entries: [BatteryHistoryEntry] {
        model.history.filter { $0.date >= Date().addingTimeInterval(-Double(days) * 86400) }
    }
    private var plotted: [BatteryHistoryEntry] {
        let values = entries, step = max(1, values.count / 360)
        var result = stride(from: 0, to: values.count, by: step).map { values[$0] }
        if let last = values.last, result.last?.id != last.id { result.append(last) }
        return result
    }
    var body: some View {
        BatterySection(title: "Historique local de la batterie") {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Période", selection: $days) {
                    Text("24 heures").tag(1); Text("7 jours").tag(7); Text("30 jours").tag(30)
                }.pickerStyle(.segmented)
                if let error = model.historyError { Label(error, systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true) }
                if entries.isEmpty {
                    Text("L’historique commence avec les mesures de MacCare. Il se remplira pendant que l’app reste ouverte.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 24)
                } else {
                    Chart(plotted) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("Niveau", entry.percent))
                        PointMark(x: .value("Date", entry.date), y: .value("Niveau", entry.percent)).symbolSize(8)
                    }.chartYScale(domain: 0...100).frame(height: 220)
                    if let first = entries.first, let last = entries.last {
                        Text("\(entries.count) relevés · de \(first.percent) % à \(last.percent) % · dernier relevé \(last.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("Santé estimée : \(last.health.map { "\($0) %" } ?? "indisponible") · cycles : \(last.cycles.map(String.init) ?? "indisponibles")")
                    }
                }
                Text("Mesures conservées sur ce Mac pendant trente jours. Aucun historique antérieur n’est reconstitué et aucune donnée n’est envoyée à un serveur.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
