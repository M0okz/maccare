import SwiftUI
import AppKit

struct DiskHealthView: View {
    @StateObject private var health = DiskHealthModel()
    @State private var volumes = DiskHealthVolume.mounted()
    @State private var selectedPath = "/"
    @State private var volumeNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(title: "Santé des disques", subtitle: "Consultez la température, l’endurance et les alertes rapportées par vos disques.")
                Picker("Disque à examiner", selection: $selectedPath) {
                    ForEach(volumes) { volume in Text(volume.name).tag(volume.path) }
                }.pickerStyle(.menu).controlSize(.large).frame(maxWidth: 520, alignment: .leading)
                if let volumeNotice { Label(volumeNotice, systemImage: "info.circle").font(AppFont.secondary).foregroundStyle(Theme.muted) }
                DiskHealthCard(model: health, volumePath: selectedPath)
                Label("Diagnostic en lecture seule", systemImage: "checkmark.shield")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }.frame(maxWidth: 820, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(Theme.window).foregroundStyle(Theme.fg)
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
