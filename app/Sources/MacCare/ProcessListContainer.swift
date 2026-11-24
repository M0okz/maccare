import AppKit

/// Les commandes de recherche partagent la ligne des titres. Le tableau garde
/// ses en-têtes AppKit pour le tri, le redimensionnement et l’accessibilité.
final class ProcessListContainer: NSView, NSTextFieldDelegate {
    static let nameIconInset: CGFloat = 24
    static let pidInset: CGFloat = 38
    let scroll = ProcessScrollView()
    var queryChanged: ((String) -> Void)?
    var isCardHovered = false {
        didSet {
            if isCardHovered != oldValue { updateSearchTint() }
        }
    }

    private let energyHelp = ProcessEnergyScore.help as NSString
    private var energyTipRect = NSRect.zero
    private var energyTipTag: NSView.ToolTipTag?
    private let field = NSTextField()
    private let searchIcon = NSImageView()
    private let button = SearchButton()
    private var header: ProcessHeader? { (scroll.documentView as? NSTableView)?.headerView as? ProcessHeader }

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.contentView.automaticallyAdjustsContentInsets = false
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.setAccessibilityElement(false)
        searchIcon.isHidden = true
        addSubview(searchIcon)

        field.placeholderString = "Rechercher par nom ou PID"
        field.setAccessibilitySubrole(.searchField)
        field.setAccessibilityLabel("Rechercher un processus par nom ou PID")
        field.font = .systemFont(ofSize: 12)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.isHidden = true
        addSubview(field)

        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(toggleSearch)
        updateButton()
        addSubview(button)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard let header, let table = header.tableView, !table.tableColumns.isEmpty else { return }
        let energy = table.column(withIdentifier: .init(HomeProcessColumn.energy.rawValue))
        let tipRect = energy >= 0 ? convert(header.headerRect(ofColumn: energy), from: header).intersection(bounds) : .zero
        if tipRect != energyTipRect {
            if let energyTipTag { removeToolTip(energyTipTag) }
            energyTipTag = tipRect.isEmpty ? nil : addToolTip(tipRect, owner: energyHelp, userData: nil)
            energyTipRect = tipRect
        }
        let first = convert(header.headerRect(ofColumn: 0), from: header)
        let right = min(bounds.maxX, convert(header.bounds, from: header).maxX)
        let iconX = first.minX + Self.nameIconInset
        searchIcon.frame = NSRect(x: iconX, y: first.midY - 7, width: 14, height: 14)
        let height = min(first.height, field.intrinsicContentSize.height)
        let fieldX = iconX + 25
        field.frame = NSRect(x: fieldX, y: (first.midY - height / 2).rounded(),
                             width: max(0, first.maxX - fieldX - 6), height: height)
        button.frame = NSRect(x: right - 32, y: first.minY, width: 28, height: first.height)
    }

    @objc private func toggleSearch() {
        let opening = field.isHidden
        field.isHidden = !opening
        searchIcon.isHidden = !opening
        header?.searching = opening
        updateButton()
        if opening {
            window?.makeFirstResponder(field)
        } else {
            field.stringValue = ""
            queryChanged?("")
            window?.makeFirstResponder(button)
        }
    }

    private func updateButton() {
        let label = field.isHidden ? "Rechercher un processus" : "Fermer la recherche"
        button.image = NSImage(systemSymbolName: field.isHidden ? "magnifyingglass" : "xmark", accessibilityDescription: nil)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        updateSearchTint()
    }

    private func updateSearchTint() {
        let tint: NSColor? = isCardHovered ? .systemBlue : nil
        button.contentTintColor = field.isHidden ? tint : nil
        searchIcon.contentTintColor = tint ?? .secondaryLabelColor
    }

    func controlTextDidChange(_ notification: Notification) { queryChanged?(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        toggleSearch()
        return true
    }

    private final class SearchButton: NSButton {
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

/// AppKit réserve normalement l’en-tête par un inset et fait défiler les lignes
/// derrière lui. Ici, seul le rectangle situé sous les titres contient des lignes.
final class ProcessScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let header = (documentView as? NSTableView)?.headerView,
              header.isDescendant(of: self) else { return }
        let frame = contentView.frame
        let overlap = frame.intersection(convert(header.bounds, from: header))
        if !overlap.isEmpty {
            contentView.frame = frame.divided(atDistance: overlap.height,
                                              from: isFlipped ? .minYEdge : .maxYEdge).remainder
        }
    }
}
