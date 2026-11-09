import SwiftUI

struct DiskHealthCard: View {
    @ObservedObject var model: DiskHealthModel
    let volumePath: String
    var showsRefresh = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.report?.warning == true ? "exclamationmark.triangle" : "internaldrive")
                    .font(.title2).foregroundStyle(model.report?.warning == true ? Theme.warn : Theme.accentInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Santé du disque").font(AppFont.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(model.isLoading ? "Lecture des informations du disque…" : model.report?.summary ?? "Informations indisponibles")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if showsRefresh {
                    Button("Actualiser") { Task { await model.refresh(at: volumePath) } }
                        .buttonStyle(.borderless).font(AppFont.secondary).disabled(model.isLoading)
                }
            }
            if let report = model.report {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 22) { metrics(report) }
                    VStack(alignment: .leading, spacing: 8) { metrics(report) }
                }.padding(.leading, 38)
                DisclosureGroup("Détails du disque") {
                    VStack(alignment: .leading, spacing: 7) {
                        if let name = report.model { Text(name).fontWeight(.semibold) }
                        if let hours = report.hours { Text("Fonctionnement : \(hours.formatted()) heures") }
                        if let cycles = report.powerCycles { Text("Mises sous tension : \(cycles.formatted())") }
                        if let bytes = report.writtenBytes { Text("Données écrites : \(humanSize(bytes))") }
                        if let errors = report.mediaErrors { Text("Erreurs d’intégrité : \(errors.formatted())") }
                        if let spare = report.spareAvailable { Text("Réserve disponible : \(spare) %") }
                        Text("Ces indicateurs sont rapportés par le disque. L’endurance consommée est une estimation du fabricant, pas une prévision de panne.")
                            .foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        if let date = model.measuredAt { Text("Relevé à \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(Theme.muted) }
                    }.font(AppFont.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(AppFont.secondary)
            } else if let message = model.message {
                Text(message).font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Theme.fg)
    }
    @ViewBuilder private func metrics(_ report: DiskHealthReport) -> some View {
        if let temperature = report.temperature { Text("\(temperature) °C").font(AppFont.body.weight(.semibold)).monospacedDigit().accessibilityLabel("Température du disque : \(temperature) degrés Celsius") }
        if let used = report.enduranceUsed { Text("\(used) % d’endurance consommée").font(AppFont.secondary).monospacedDigit() }
    }
}
