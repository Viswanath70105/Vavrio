import AppKit

struct MarkdownEntry: Sendable {
    let url: URL
    let isDirectory: Bool

    static func read(_ directory: URL) throws -> [MarkdownEntry] {
        try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]).compactMap { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { return nil }
                if values.isDirectory == true { return MarkdownEntry(url: url, isDirectory: true) }
                guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { return nil }
                return MarkdownEntry(url: url, isDirectory: false)
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }
}

@MainActor
final class MarkdownBrowser: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        let entry: MarkdownEntry
        var children: [Node] = []
        var requested = false
        init(_ entry: MarkdownEntry) { self.entry = entry }
    }
    let view = NSScrollView()
    private let outline = NSOutlineView()
    private var root: Node?
    var rootURL: URL? { root?.entry.url }
    private var selectedURL: URL?
    private var generation = UUID()
    private var synchronizingSelection = false
    var onOpen: ((URL) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("files"))
        column.title = "Markdown Files"; column.width = 220
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.dataSource = self; outline.delegate = self
        outline.target = self; outline.action = #selector(clicked)
        outline.rowHeight = 30
        outline.style = .sourceList
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = true
        view.documentView = outline; view.hasVerticalScroller = true
        view.hasHorizontalScroller = true
    }
    func open(_ url: URL) {
        generation = UUID()
        root = Node(MarkdownEntry(url: url, isDirectory: true))
        outline.tableColumns.first?.title = url.lastPathComponent
        outline.reloadData()
        if let root { load(root) }
    }
    func selectFile(_ url: URL?) {
        selectedURL = url
        synchronizingSelection = true
        defer { synchronizingSelection = false }
        guard let url else { outline.deselectAll(nil); return }
        func locate(_ node: Node) -> [Node]? {
            if node.entry.url.standardizedFileURL == url.standardizedFileURL { return [node] }
            for child in node.children {
                if let path = locate(child) { return [node] + path }
            }
            return nil
        }
        guard let root, let path = locate(root), let leaf = path.last else { outline.deselectAll(nil); return }
        for node in path.dropFirst().dropLast() { outline.expandItem(node) }
        let row = outline.row(forItem: leaf)
        if row >= 0 {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }
    func refresh(selecting url: URL? = nil) {
        if let url { selectedURL = url }
        if let root { open(root.entry.url) }
    }
    private func load(_ node: Node) {
        guard !node.requested else { return }
        node.requested = true
        let token = generation
        let url = node.entry.url
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try MarkdownEntry.read(url) } }.value
            guard generation == token else { return }
            switch result {
            case .success(let entries):
                node.children = entries.map(Node.init)
                if node === root { outline.reloadData() }
                else { outline.reloadItem(node, reloadChildren: true) }
                if let selectedURL {
                    // Load only the selected document’s ancestor chain after refresh.
                    for child in node.children where child.entry.isDirectory {
                        let prefix = child.entry.url.standardizedFileURL.path + "/"
                        if selectedURL.standardizedFileURL.path.hasPrefix(prefix) { load(child) }
                    }
                    selectFile(selectedURL)
                }
            case .failure(let error):
                node.requested = false
                onError?("\(url.path): \(error.localizedDescription)")
            }
        }
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? Node) ?? root)?.children.count ?? 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Node) ?? root)!.children[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.entry.isDirectory ?? false
    }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        if let node = item as? Node { load(node) }
        return true
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: node.entry.isDirectory ? "folder" : "doc.text", accessibilityDescription: nil)
        icon.contentTintColor = node.entry.isDirectory ? .systemBlue : .secondaryLabelColor
        let label = NSTextField(labelWithString: node.entry.url.lastPathComponent)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13)
        cell.toolTip = node.entry.url.path
        cell.textField = label; cell.imageView = icon
        for child in [icon, label] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6)
        ])
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !synchronizingSelection, outline.selectedRow >= 0, let node = outline.item(atRow: outline.selectedRow) as? Node,
              !node.entry.isDirectory else { return }
        onOpen?(node.entry.url)
    }
    @objc private func clicked() {
        guard outline.clickedRow >= 0, let node = outline.item(atRow: outline.clickedRow) as? Node else { return }
        if node.entry.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else { onOpen?(node.entry.url) }
    }
}
