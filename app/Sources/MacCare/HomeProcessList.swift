import AppKit
import SwiftUI

/// AppKit conserve le défilement et les colonnes redimensionnables pendant les relevés.
struct HomeProcessList: NSViewRepresentable {
    let rows: [HomeProcessGroup]
    let processCount: Int
    let cpuSummary: String
    let controller: TrayProcessController
    let isCardHovered: Bool
    @Binding var sort: HomeProcessSort
    @Binding var query: String
    let open: (HomeProcessGroup) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ProcessListContainer {
        let container = ProcessListContainer()
        let scroll = container.scroll
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let table = ProcessTableView()
        table.style = .plain
        table.backgroundColor = .clear
        table.headerView = ProcessHeader(frame: NSRect(x: 0, y: 0, width: 0, height: ProcessHeader.height))
        table.rowHeight = 30
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        table.setAccessibilityLabel("Processus par application")
        for field in HomeProcessColumn.allCases {
            let column = NSTableColumn(identifier: .init(field.rawValue))
            column.title = field.rawValue
            column.width = [.name: 280, .memory: 105, .cpu: 156, .energy: 112, .pid: 108][field]!
            column.minWidth = [.name: 115, .memory: 76, .cpu: 120, .energy: 84, .pid: 88][field]!
            column.resizingMask = field == .name ? [.userResizingMask, .autoresizingMask] : [.userResizingMask]
            column.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: field == .name || field == .pid)
            if field == .energy {
                column.headerToolTip = ProcessEnergyScore.help
                column.headerCell.setAccessibilityHelp(ProcessEnergyScore.help)
            }
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
        container.queryChanged = { [weak coordinator = context.coordinator] text in coordinator?.owner.query = text }
        return container
    }

    func updateNSView(_ container: ProcessListContainer, context: Context) {
        container.isCardHovered = isCardHovered
        guard let table = container.scroll.documentView as? ProcessTableView,
              let name = table.tableColumns.first else { return }
        let title = "Nom (\(rows.count.formatted()))"
        if name.title != title { name.title = title; table.headerView?.needsDisplay = true }
        let summary = cpuSummary.isEmpty ? "Trier par nom" : "Applications au-dessus de 40 % de CPU\n" + cpuSummary
        name.headerToolTip = "\(processCount.formatted()) processus relevés avant regroupement.\n" + summary
        let coordinator = context.coordinator
        let selection = coordinator.owner.rows.indices.contains(table.selectedRow) ? coordinator.owner.rows[table.selectedRow].id : nil
        let countChanged = coordinator.owner.rows.count != rows.count
        coordinator.owner = self
        table.reloadData()
        if countChanged { table.window?.invalidateCursorRects(for: table) }
        if let selection, let index = rows.firstIndex(where: { $0.id == selection }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        table.refreshHover()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var owner: HomeProcessList
        init(_ owner: HomeProcessList) { self.owner = owner }
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let table = notification.object as? NSTableView else { return }
            table.enclosingScrollView?.superview?.needsLayout = true
        }
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
                cell.indicator?.fillColor = group.cpuLevel.accent ?? .labelColor.withAlphaComponent(0.13)
                cell.label.stringValue = group.name
                cell.imageView?.image = owner.controller.presentation(for: group.representative).icon
                    ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
                cell.toolTip = group.application?.path ?? group.members[0].executable
            case .memory: cell.label.stringValue = HomeProcessMetric.memory(group.memory)
            case .cpu:
                cell.label.stringValue = group.cpuLabel
                cell.meter?.value = min(1, (group.cpu ?? 0) / 100)
                cell.meter?.cpuLevel = group.cpuLevel
            case .energy:
                cell.label.stringValue = group.energyScore?.number ?? "—"
                let partial = group.energyScore?.isLowerBound == true ? " Certaines mesures manquent. La note indique un minimum." : ""
                cell.toolTip = ProcessEnergyScore.help + partial
                cell.label.setAccessibilityHelp(cell.toolTip)
            case .pid:
                cell.label.stringValue = String(group.representative.id.pid)
                cell.toolTip = group.primary == nil
                    ? "PID de \(group.representative.name), membre affiché du groupe selon son empreinte mémoire."
                    : "PID de \(group.representative.name)."
            }
            let accent = field == .energy ? ProcessCPULevel(group.energyScore.map { $0.value * 5 }).accent
                : (field == .cpu ? group.cpuLevel.accent : nil)
            cell.label.textColor = accent ?? (field == .pid ? .secondaryLabelColor : .labelColor)
            return cell
        }
    }
}

private final class ProcessTableView: NSTableView {
    var openSelection: ((Int) -> Void)?
    private var tracking: NSTrackingArea?
    private(set) var hoverIndex = -1
    override func resetCursorRects() {
        super.resetCursorRects()
        guard numberOfRows > 0 else { return }
        let occupied = rect(ofRow: 0).union(rect(ofRow: numberOfRows - 1)).intersection(visibleRect)
        if !occupied.isEmpty { addCursorRect(occupied, cursor: .pointingHand) }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if visibleRect.contains(point), row(at: point) >= 0 { NSCursor.pointingHand.set() }
        else { super.cursorUpdate(with: event) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect], owner: self)
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
    var open: (() -> Bool)?
    override func accessibilityPerformPress() -> Bool { open?() ?? false }
    override func drawBackground(in dirtyRect: NSRect) {
        if hovered {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
    }
}

final class ProcessHeader: NSTableHeaderView {
    static let height: CGFloat = 25
    var searching = false { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }

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
        for (index, column) in table.tableColumns.enumerated() {
            if searching && index == 0 { continue }
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }
            let sort = table.sortDescriptors.first
            let selected = sort?.key == column.identifier.rawValue
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor]
            let title = column.identifier.rawValue == HomeProcessColumn.cpu.rawValue ? "% CPU" : column.title.uppercased()
            let label = title + (selected ? (sort?.ascending == true ? "  ▴" : "  ▾") : "")
            let size = (label as NSString).size(withAttributes: attributes)
            let trailing: CGFloat = column.identifier.rawValue == HomeProcessColumn.pid.rawValue ? ProcessListContainer.pidInset : 14
            let x = index == 0 ? rect.minX + ProcessListContainer.nameIconInset : rect.maxX - trailing - size.width
            (label as NSString).draw(at: CGPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}

private final class ProcessCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    private(set) var meter: ProcessMeter?
    private(set) var indicator: NSBox?
    init(_ field: HomeProcessColumn) {
        super.init(frame: .zero)
        identifier = .init(field.rawValue)
        label.lineBreakMode = .byTruncatingTail
        label.font = field == .name ? .systemFont(ofSize: 13, weight: .medium) : .monospacedDigitSystemFont(ofSize: 12, weight: field == .energy ? .semibold : .regular)
        label.alignment = field == .name ? .left : .right
        textField = label
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        var leading = leadingAnchor
        if field == .name {
            let icon = NSImageView()
            imageView = icon
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityElement(false)
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)

            let marker = NSBox()
            marker.boxType = .custom
            marker.borderType = .noBorder
            marker.titlePosition = .noTitle
            marker.cornerRadius = 1
            marker.setAccessibilityElement(false)
            marker.translatesAutoresizingMaskIntoConstraints = false
            addSubview(marker)
            indicator = marker
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ProcessListContainer.nameIconInset),
                icon.widthAnchor.constraint(equalToConstant: 17),
                icon.heightAnchor.constraint(equalToConstant: 17),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                marker.trailingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -9),
                marker.widthAnchor.constraint(equalToConstant: 3),
                marker.heightAnchor.constraint(equalToConstant: 15),
                marker.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            leading = icon.trailingAnchor
        } else if field == .cpu {
            let gauge = ProcessMeter()
            meter = gauge
            gauge.setAccessibilityElement(false)
            gauge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(gauge)
            NSLayoutConstraint.activate([
                gauge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
                gauge.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1.0 / 3),
                gauge.heightAnchor.constraint(equalToConstant: 5),
                gauge.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            leading = gauge.trailingAnchor
        }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leading, constant: field == .name ? 8 : 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: field == .pid ? -ProcessListContainer.pidInset : -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { nil }
}

private final class ProcessMeter: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var cpuLevel = ProcessCPULevel.normal { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5).fill()
        guard value > 0 else { return }
        (cpuLevel.accent ?? NSColor(hex: "#BEA8EC")).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(1, bounds.width * value), height: bounds.height),
                     xRadius: 2.5, yRadius: 2.5).fill()
    }
}
