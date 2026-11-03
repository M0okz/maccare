import SwiftUI
import MacCareBattery

struct BatteryProfilesView: View {
    @ObservedObject var model: BatteryModel
    @State private var name = ""
    var body: some View {
        GroupBox("Profils d’utilisation") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(model.profiles) { profile in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.headline)
                            Text("Limite de \(profile.configuration.limit) %" + (profile.configuration.sailingWidth.map { " · maintien de \(profile.configuration.limit - $0) à \(profile.configuration.limit) %" } ?? ""))
                            if let reason = profile.unavailableReason(for: model.protection?.capabilities) {
                                Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button("Appliquer") { Task { await model.applyProfile(profile) } }
                            .help("Appliquer le profil \(profile.name)")
                            .disabled(model.controlsBusy || model.cycle != nil || profile.unavailableReason(for: model.protection?.capabilities) != nil)
                        Button("Supprimer") { model.deleteProfile(profile.id) }.disabled(model.controlsBusy)
                            .help("Supprimer le profil \(profile.name)")
                    }
                    Divider()
                }
                TextField("Nom du profil", text: $name).textFieldStyle(.roundedBorder)
                Button("Enregistrer les réglages actuels dans un profil") {
                    model.saveProfile(name: name)
                    if model.error == nil { name = "" }
                }.disabled(model.controlsBusy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("L’enregistrement conserve vos réglages de cet onglet. Le bouton Appliquer active le profil choisi.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(12)
        }
    }
}
