import AppKit
import SwiftUI

/// NSMenuDelegate fournit un événement d’ouverture natif : clic, clavier et accessibilité.
struct VolumeLocationMenu: NSViewRepresentable {
    @ObservedObject var model: SpaceModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.controlSize = .large
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.contentTintColor = NSColor(Theme.fg)
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("Emplacement à explorer")
        button.setAccessibilityHelp("Choisir un disque monté ou un dossier à explorer")
        context.coordinator.button = button
        context.coordinator.rebuild()
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.model = model
        if !context.coordinator.tracking { context.coordinator.rebuild() }
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var model: SpaceModel
        weak var button: NSPopUpButton?
        var tracking = false

        init(model: SpaceModel) { self.model = model }

        func menuNeedsUpdate(_ menu: NSMenu) {
            model.refreshVolumes()
            rebuild(menu)
        }

        func menuWillOpen(_ menu: NSMenu) { tracking = true }
        func menuDidClose(_ menu: NSMenu) {
            tracking = false
            DispatchQueue.main.async { [weak self] in self?.rebuild() }
        }

        func rebuild(_ existing: NSMenu? = nil) {
            guard let button else { return }
            let menu = existing ?? NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            menu.removeAllItems()
            for root in model.locationChoices {
                let title = root.path == "/" ? root.name.replacingOccurrences(of: " · disque de démarrage", with: "") : root.name
                let item = NSMenuItem(title: title, action: #selector(selectLocation(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = root
                item.state = root == model.root ? .on : .off
                let disk = model.volumes.contains { $0.path == root.path }
                item.image = NSImage(systemSymbolName: disk ? "internaldrive.fill" : "folder.fill", accessibilityDescription: nil)
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let choose = NSMenuItem(title: "Choisir un dossier…", action: #selector(chooseFolder), keyEquivalent: "")
            choose.target = self
            choose.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            menu.addItem(choose)
            if existing == nil { button.menu = menu }
            let selected = menu.items.first { ($0.representedObject as? SpaceModel.Root) == model.root }
            button.select(selected)
            button.setAccessibilityValue(selected?.title)
        }

        @objc private func selectLocation(_ sender: NSMenuItem) {
            guard let root = sender.representedObject as? SpaceModel.Root else { return }
            model.setRoot(root, measure: false)
            rebuild()
        }

        @objc private func chooseFolder() {
            // L’action n’est pas une destination : conserver le libellé du volume courant.
            rebuild()
            model.chooseFolder()
        }
    }
}
