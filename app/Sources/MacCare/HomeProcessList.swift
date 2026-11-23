import AppKit
import SwiftUI

/// AppKit conserve le défilement et les colonnes redimensionnables pendant les relevés.
struct HomeProcessList: NSViewRepresentable {
    let rows: [HomeProcessGroup]
    let controller: TrayProcessController
    @Binding var sort: HomeProcessSort
    let open: (HomeProcessGroup) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let table = ProcessTableView()
        table.style = .plain
        table.backgroundColor = .clear
        table.headerView = ProcessHeader()
        table.rowHeight = 27
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        table.setAccessibilityLabel("Processus par application")
        for field in HomeProcessColumn.allCases {
            let column = NSTableColumn(identifier: .init(field.rawValue))
            column.title = field.rawValue
            column.width = [.name: 280, .memory: 105, .cpu: 124, .power: 112, .pid: 80][field]!
            column.minWidth = [.name: 115, .memory: 76, .cpu: 88, .power: 84, .pid: 56][field]!
            column.resizingMask = field == .name ? [.userResizingMask, .autoresizingMask] : [.userResizingMask]
            column.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: field == .name || field == .pid)
            if field == .power { column.headerToolTip = "Puissance moyenne estimée par macOS sur le dernier intervalle." }
            if field == .cpu { column.headerToolTip = "100 % correspond à un cœur utilisé." }
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: sort.column.rawValue, ascending: sort.ascending)]
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:))
        table.openSelection = { [weak coordinator = context.coordinator] index in coordinator?.show(index) }
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? ProcessTableView else { return }
        let coordinator = context.coordinator
        let selection = coordinator.owner.rows.indices.contains(table.selectedRow) ? coordinator.owner.rows[table.selectedRow].id : nil
        coordinator.owner = self
        table.reloadData()
        if let selection, let index = rows.firstIndex(where: { $0.id == selection }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        table.refreshHover()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var owner: HomeProcessList
        init(_ owner: HomeProcessList) { self.owner = owner }
        func numberOfRows(in tableView: NSTableView) -> Int { owner.rows.count }
        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            // Le clic ouvre la fiche ; seule la navigation au clavier conserve une sélection.
            sender.deselectAll(nil)
            show(row)
        }
        func show(_ index: Int) {
            guard owner.rows.indices.contains(index) else { return }
            owner.open(owner.rows[index])
        }
        func tableView(_ table: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            guard let descriptor = table.sortDescriptors.first, let key = descriptor.key,
                  let column = HomeProcessColumn(rawValue: key) else { return }
            owner.sort = HomeProcessSort(column: column, ascending: descriptor.ascending)
            table.headerView?.needsDisplay = true
        }
        func tableView(_ table: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = ProcessRowView()
            view.hot = owner.rows[row].highCPU
            view.hovered = (table as? ProcessTableView)?.hoverIndex == row
            view.open = { [weak self, weak table, weak view] in
                guard let table, let view else { return false }
                let index = table.row(for: view)
                guard index >= 0 else { return false }
                self?.show(index)
                return true
            }
            return view
        }
        func tableView(_ table: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard let column, let field = HomeProcessColumn(rawValue: column.identifier.rawValue) else { return nil }
            let cell = table.makeView(withIdentifier: column.identifier, owner: self) as? ProcessCell ?? ProcessCell(field)
            let group = owner.rows[row]
            switch field {
            case .name:
                cell.label.stringValue = group.name
                cell.imageView?.image = owner.controller.presentation(for: group.primary ?? group.members[0]).icon
                    ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
                cell.toolTip = group.application?.path ?? group.members[0].executable
            case .memory: cell.label.stringValue = HomeProcessMetric.memory(group.memory)
            case .cpu:
                cell.label.stringValue = group.cpuLabel
                cell.meter?.value = min(1, (group.cpu ?? 0) / 100)
                cell.meter?.hot = group.highCPU
            case .power:
                cell.label.stringValue = group.powerLabel
                cell.toolTip = "Somme des puissances mesurées sur le dernier intervalle."
            case .pid: cell.label.stringValue = group.primary.map { String($0.id.pid) } ?? "—"
            }
            let hotMetric = group.highCPU && (field == .cpu || field == .power)
            cell.label.textColor = hotMetric ? .systemOrange : (field == .pid ? .secondaryLabelColor : .labelColor)
            return cell
        }
    }
}

private final class ProcessTableView: NSTableView {
    var openSelection: ((Int) -> Void)?
    private var tracking: NSTrackingArea?
    private(set) var hoverIndex = -1
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { refreshHover() }
    override func mouseMoved(with event: NSEvent) { refreshHover() }
    override func mouseExited(with event: NSEvent) { setHover(-1) }
    override func scrollWheel(with event: NSEvent) { super.scrollWheel(with: event); refreshHover() }
    func refreshHover() {
        guard let window, window.isKeyWindow else { setHover(-1); return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHover(visibleRect.contains(point) ? row(at: point) : -1)
    }
    private func setHover(_ index: Int) {
        guard index != hoverIndex else { return }
        let previous = hoverIndex
        hoverIndex = index
        for i in [previous, index] where i >= 0 && i < numberOfRows {
            (rowView(atRow: i, makeIfNecessary: false) as? ProcessRowView)?.hovered = i == index
        }
    }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode), selectedRow >= 0 { openSelection?(selectedRow) }
        else { super.keyDown(with: event) }
    }
}

private final class ProcessRowView: NSTableRowView {
    var hovered = false { didSet { needsDisplay = true } }
    var hot = false
    var open: (() -> Bool)?
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(visibleRect, cursor: .pointingHand)
    }
    override func accessibilityPerformPress() -> Bool { open?() ?? false }
    override func drawBackground(in dirtyRect: NSRect) {
        if hovered {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        if hot {
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 6, width: 3, height: bounds.height - 12), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

private final class ProcessHeader: NSTableHeaderView {
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let tableView else { return }
        for (index, column) in tableView.tableColumns.enumerated() where column.sortDescriptorPrototype != nil {
            // Leave the column edges to the native resize cursor.
            let rect = headerRect(ofColumn: index).insetBy(dx: 5, dy: 0).intersection(visibleRect)
            if !rect.isEmpty { addCursorRect(rect, cursor: .pointingHand) }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let table = tableView else { return }
        NSColor.white.withAlphaComponent(0.04).setFill()
        dirtyRect.fill()
        for (index, column) in table.tableColumns.enumerated() {
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }
            let sort = table.sortDescriptors.first
            let selected = sort?.key == column.identifier.rawValue
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor]
            let label = column.title + (selected ? (sort?.ascending == true ? "  ▴" : "  ▾") : "")
            let size = (label as NSString).size(withAttributes: attributes)
            let x = index == 0 ? rect.minX + 14 : rect.maxX - 14 - size.width
            (label as NSString).draw(at: CGPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}

private final class ProcessCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    var meter: ProcessMeter?
    init(_ field: HomeProcessColumn) {
        super.init(frame: .zero)
        identifier = .init(field.rawValue)
        label.lineBreakMode = .byTruncatingTail
        label.font = field == .name ? .systemFont(ofSize: 13, weight: .medium) : .monospacedDigitSystemFont(ofSize: 12, weight: field == .power ? .semibold : .regular)
        label.alignment = field == .name ? .left : .right
        textField = label
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        var leading = leadingAnchor
        if field == .name || field == .cpu {
            let visual: NSView
            let width: CGFloat
            if field == .name {
                let icon = NSImageView()
                imageView = icon
                icon.imageScaling = .scaleProportionallyUpOrDown
                visual = icon
                width = 17
            } else {
                let gauge = ProcessMeter()
                meter = gauge
                visual = gauge
                width = 32
            }
            visual.setAccessibilityElement(false)
            addSubview(visual)
            visual.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([visual.leadingAnchor.constraint(equalTo: leading, constant: 13),
                visual.widthAnchor.constraint(equalToConstant: width), visual.heightAnchor.constraint(equalToConstant: field == .name ? 17 : 5),
                visual.centerYAnchor.constraint(equalTo: centerYAnchor)])
            leading = visual.trailingAnchor
        }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leading, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { nil }
}

private final class ProcessMeter: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var hot = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5).fill()
        guard value > 0 else { return }
        (hot ? NSColor.systemOrange : NSColor(hex: "#BEA8EC")).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(1, bounds.width * value), height: bounds.height),
                     xRadius: 2.5, yRadius: 2.5).fill()
    }
}
