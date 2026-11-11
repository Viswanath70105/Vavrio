import AppKit

@MainActor
private final class NavigationResultsTable: NSTableView {
    var accept: (() -> Void)?
    var dismiss: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: accept?()
        case 53: dismiss?()
        default: super.keyDown(with: event)
        }
    }
}

/// A native sheet: search, arrows, Return to choose, Escape to dismiss.
@MainActor
final class NavigationPalette: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let panel: NSPanel
    private let search = NSSearchField()
    private let table = NavigationResultsTable()
    var selectedID: String? { matches.indices.contains(table.selectedRow) ? matches[table.selectedRow].id : nil }
    private let footer = NSTextField(labelWithString: "")
    private var items: [NavigationItem] = []
    private(set) var matches: [NavigationItem] = []
    private var status = ""
    private var finished = false
    private var chosenID: String?
    var onFinish: ((String?) -> Void)?

    init(title: String, placeholder: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 430),
                        styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = title
        search.placeholderString = placeholder
        search.font = .systemFont(ofSize: 18)
        search.sendsSearchStringImmediately = true
        search.delegate = self
        search.setAccessibilityLabel(title)
        let column = NSTableColumn(identifier: .init("results"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 52
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .fullWidth
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(choose)
        table.accept = { [weak self] in self?.choose() }
        table.dismiss = { [weak self] in self?.cancel() }
        table.setAccessibilityLabel("Search results")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = table
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingMiddle
        let hint = NSTextField(labelWithString: "↑↓ Navigate     ↩ Open     esc Close")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let bottom = NSStackView(views: [hint, NSView(), cancel])
        let content = NSView()
        for view in [search, scroll, footer, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -8),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        panel.contentView = content
    }
    func present(on window: NSWindow) {
        window.beginSheet(panel) { [weak self] _ in
            guard let self else { return }
            panel.orderOut(nil)
            onFinish?(chosenID)
        }
        panel.makeFirstResponder(search)
    }
    func update(_ items: [NavigationItem], status: String) {
        self.items = items; self.status = status
        filter(preservingSelection: true)
    }
    func setQuery(_ value: String) { search.stringValue = value; filter(preservingSelection: false) }
    private func filter(preservingSelection: Bool) {
        let previous = preservingSelection ? selectedID : nil
        matches = NavigationSearch.ranked(items, query: search.stringValue)
        table.reloadData()
        if !matches.isEmpty {
            let selected = matches.firstIndex { $0.id == previous && $0.enabled } ?? matches.firstIndex { $0.enabled } ?? 0
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
            table.scrollRowToVisible(selected)
        }
        footer.stringValue = matches.isEmpty ? "No matches. " + status : "\(matches.count) shown · " + status
        footer.toolTip = footer.stringValue
    }
    func controlTextDidChange(_ obj: Notification) { filter(preservingSelection: false) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): choose(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancel(); return true
        default: return false
        }
    }
    private func move(_ offset: Int) {
        guard !matches.isEmpty else { return }
        var row = table.selectedRow + offset
        while matches.indices.contains(row) {
            if matches[row].enabled {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                table.scrollRowToVisible(row)
                return
            }
            row += offset
        }
    }
    @objc func choose() {
        guard matches.indices.contains(table.selectedRow), matches[table.selectedRow].enabled else { return }
        finish(matches[table.selectedRow].id)
    }
    @objc func cancel() { finish(nil) }
    private func finish(_ id: String?) {
        guard !finished else { return }
        finished = true
        chosenID = id
        if let parent = panel.sheetParent { parent.endSheet(panel) }
        else { panel.orderOut(nil); onFinish?(id) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = matches[row]
        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let detail = NSTextField(labelWithString: item.detail)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        title.textColor = item.enabled ? .labelColor : .tertiaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 3
        let key = NSTextField(labelWithString: item.shortcut)
        key.font = .monospacedSystemFont(ofSize: 11, weight: .regular); key.textColor = .secondaryLabelColor
        let rowView = NSView()
        for view in [text, key] { view.translatesAutoresizingMaskIntoConstraints = false; rowView.addSubview(view) }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: key.leadingAnchor, constant: -10),
            key.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -12),
            key.centerYAnchor.constraint(equalTo: rowView.centerYAnchor)
        ])
        rowView.toolTip = item.detail
        return rowView
    }
}
