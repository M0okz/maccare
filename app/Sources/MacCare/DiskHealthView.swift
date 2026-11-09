import SwiftUI
import AppKit

struct DiskHealthView: View {
    @StateObject private var health = DiskHealthModel()
    @State private var volumes = DiskHealthVolume.mounted()
    @State private var selectedPath = "/"
    @State private var volumeNotice: String?
    private var selectedVolume: DiskHealthVolume? { volumes.first { $0.path == selectedPath } }

    var body: some View {
        ManagerBrowserLayout {
            VStack(alignment: .leading, spacing: 16) {
                Text("Santé des disques").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                Text("Choisissez un disque pour consulter ses indicateurs matériels.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(volumes) { volume in
                    Button { selectedPath = volume.path } label: {
                        Label(volume.name, systemImage: volume.path == "/" ? "internaldrive" : "externaldrive")
                            .font(AppFont.body.weight(.medium)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(10)
                            .background(selectedPath == volume.path ? Theme.accent.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedPath == volume.path ? .isSelected : [])
                }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(selectedVolume?.name ?? "Santé du disque").font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text("Consultez la température, l’endurance et les alertes rapportées par ce disque.")
                        .font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    if let volumeNotice { Label(volumeNotice, systemImage: "info.circle").foregroundStyle(Theme.muted) }
                    DiskHealthCard(model: health, volumePath: selectedPath, showsRefresh: false)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            }
        } footer: {
            AdaptiveActionRow {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Diagnostic en lecture seule", systemImage: "checkmark.shield").font(AppFont.body.weight(.semibold))
                    Text(health.isLoading ? "Lecture des informations du disque…" : health.measuredAt.map {
                        "Relevé à \($0.formatted(date: .omitted, time: .shortened))"
                    } ?? "Aucune mesure disponible.").font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            } actions: {
                Button("Actualiser", systemImage: "arrow.clockwise") { Task { await health.refresh(at: selectedPath) } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(health.isLoading)
            }.padding(18).background(Theme.sidebar)
        }
        .task(id: selectedPath) { await health.refresh(at: selectedPath) }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in refreshVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in refreshVolumes() }
    }

    private func refreshVolumes() {
        volumes = DiskHealthVolume.mounted()
        if !volumes.contains(where: { $0.path == selectedPath }) {
            selectedPath = "/"
            volumeNotice = "Le disque précédent a été déconnecté. Le disque de démarrage est sélectionné."
        } else { volumeNotice = nil }
    }
}
