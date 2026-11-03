import AppKit
import SwiftUI

struct FileSearchLocationMenu: NSViewRepresentable {
    @ObservedObject var model: FilesAnalysisModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false; button.controlSize = .large
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.contentTintColor = .white
        button.setAccessibilityLabel("Dossier à analyser")
        context.coordinator.button = button
        context.coordinator.rebuild()
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = context.environment.isEnabled
        context.coordinator.model = model
        context.coordinator.rebuild()
    }
    @MainActor final class Coordinator: NSObject {
        var model: FilesAnalysisModel
        weak var button: NSPopUpButton?
        init(_ model: FilesAnalysisModel) { self.model = model }
        func rebuild() {
            guard let button else { return }
            let menu = NSMenu()
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let roots = model.searchRoot == home ? [home] : [home, model.searchRoot]
            for root in roots {
                let item = NSMenuItem(title: root.lastPathComponent, action: #selector(selectRoot(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = root
                item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let choose = NSMenuItem(title: "Choisir un dossier…", action: #selector(chooseFolder), keyEquivalent: "")
            choose.target = self; choose.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(choose)
            button.menu = menu
            button.select(menu.items.first { ($0.representedObject as? URL) == model.searchRoot })
            button.setAccessibilityValue(model.searchRoot.path)
            button.toolTip = model.searchRoot.path
        }
        @objc func selectRoot(_ sender: NSMenuItem) {
            if let root = sender.representedObject as? URL { model.setRoot(root) }
        }
        @objc func chooseFolder() {
            rebuild()
            model.chooseFolder()
        }
    }
}
