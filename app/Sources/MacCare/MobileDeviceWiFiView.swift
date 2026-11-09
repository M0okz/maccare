import SwiftUI

struct MobileDeviceWiFiView: View {
    @StateObject private var model = MobileDeviceWiFiModel()
    @AccessibilityFocusState private var feedbackFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Appareils Apple").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { Task { await model.refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(SecondaryActionButtonStyle()).disabled(model.busy)
            }
            Text("Suivez la batterie de l’iPhone ou de l’iPad, et le dernier niveau connu de sa Watch, depuis ce Mac.")
                .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if model.busy { ProgressView("Lecture de l’appareil…").controlSize(.small) }
            if model.loaded && model.devices.isEmpty {
                Text("Aucun appareil joignable. Pour configurer l’accès Wi-Fi, branchez l’iPhone ou l’iPad en USB, déverrouillez-le et acceptez « Faire confiance » si demandé, puis actualisez.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.devices) { device in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).font(.headline)
                            Text(device.wifiEnabled.map { $0 ? "Accès Wi-Fi activé" : "Accès Wi-Fi désactivé" } ?? "État Wi-Fi indisponible")
                                .font(.callout).foregroundStyle(Theme.muted)
                        }.accessibilityElement(children: .combine)
                        Spacer(minLength: 16)
                        if let enabled = device.wifiEnabled {
                            Button(enabled ? "Désactiver l’accès Wi-Fi" : "Activer l’accès Wi-Fi") {
                                Task { await model.setWiFi(for: device, enabled: !enabled) }
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(model.busy || !device.canConfigure)
                        }
                    }
                    if !device.usbConnected {
                        Text("Rebranchez le câble USB pour modifier cet accès.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    } else if !device.canConfigure {
                        Text("Ce réglage n’est pas accessible depuis MacCare. Vous pouvez le modifier dans le Finder.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            Text("C’est la même option que « Afficher cet iPhone lorsqu’il est en Wi-Fi » dans le Finder. MacCare la modifie uniquement lorsque vous cliquez sur le bouton.")
                .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let message = model.message {
                Label(message, systemImage: model.isError ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(model.isError ? Theme.warn : Theme.ok)
                    .fixedSize(horizontal: false, vertical: true).accessibilityFocused($feedbackFocused)
            }
        }
        .padding(24).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
        .task { await model.refresh() }
        .onChange(of: model.message) { feedbackFocused = $0 != nil }
    }
}
