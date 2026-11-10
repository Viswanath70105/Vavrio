import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorWindowController: NSWindowController, NSMenuItemValidation, NSWindowDelegate, NSTextViewDelegate {
    private var textView: NSTextView?
    private let emptySession = DocumentSession()
    private var session: DocumentSession { active?.session ?? emptySession }
    private(set) var documents: [EditorDocument] = []
    private(set) var active: EditorDocument?
    private let editorHost = NSView()
    private let tabs = NSStackView()
    private let reader = MarkdownReader()
    private let documentSplit = NSSplitView()
    private var readerVisible = false
    private var readerButton: NSButton?
    private let browser = MarkdownBrowser()
    private var operationPending = false
    var busy: Bool { operationPending || documents.contains { $0.session.isWorking } }
    private var editorUndoManager: UndoManager { active?.undoManager ?? emptyUndoManager }
    private let emptyUndoManager = UndoManager()
    private var openButton: NSButton?
    private var saveButton: NSButton?
    private var cancelButton: NSButton?
    private var statusLabel: NSTextField?
    private var transitionActive = false
    private var allowClose = false
    private var allowTermination = false

    enum UnsavedDecision { case save, discard, cancel }
    private let decision: (@MainActor (EditorDocument) async -> UnsavedDecision)?
    init(decision: (@MainActor (EditorDocument) async -> UnsavedDecision)? = nil) {
        self.decision = decision
        super.init(window: nil)
        configureWindow(show: false)
    }
    required init?(coder: NSCoder) { fatalError("Use init(decision:)") }

    func configureWindow(show: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let container = NSView()
        let openButton = NSButton(title: "Open Folder…", target: self, action: #selector(openFolder(_:)))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveDocument(_:)))
        let cancelButton = NSButton(title: "Cancel Open", target: self, action: #selector(cancelOpen(_:)))
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshFolder(_:)))
        let close = NSButton(title: "Reader", target: self, action: #selector(toggleReader(_:)))
        close.setButtonType(.pushOnPushOff)
        close.toolTip = "Show or hide the rendered Markdown reader"
        readerButton = close
        let buttons = NSStackView(views: [openButton, refresh, saveButton, cancelButton, close])
        tabs.orientation = .horizontal
        tabs.spacing = 4
        let tabScroll = NSScrollView()
        tabScroll.hasHorizontalScroller = true
        tabScroll.documentView = tabs
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor).isActive = true
        tabs.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor).isActive = true
        tabs.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(browser.view)
        documentSplit.isVertical = true
        documentSplit.dividerStyle = .thin
        documentSplit.addArrangedSubview(editorHost)
        documentSplit.addArrangedSubview(reader.view)
        reader.view.isHidden = true
        split.addArrangedSubview(documentSplit)
        browser.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        editorHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        browser.onOpen = { [weak self] url in self?.openURL(url) }
        browser.onError = { [weak self] message in
            self?.statusLabel?.stringValue = "Couldn’t read folder: " + message
        }
        buttons.spacing = 8
        let status = NSTextField(labelWithString: session.status)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        for view in [buttons, tabScroll, split, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            buttons.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            tabScroll.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            tabScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabScroll.heightAnchor.constraint(equalToConstant: 44),
            split.topAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        window.contentView = container
        self.window = window
        self.openButton = openButton; self.saveButton = saveButton
        self.cancelButton = cancelButton; self.statusLabel = status
        container.layoutSubtreeIfNeeded()
        split.setPosition(220, ofDividerAt: 0)
        window.center()
        if show { window.makeKeyAndOrderFront(nil) }
        window.makeFirstResponder(self.textView)
        updateUI()
        if show { NSApplication.shared.activate() }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { editorUndoManager }
    func textDidChange(_ notification: Notification) {
        guard let source = notification.object as? NSTextView,
              let document = documents.first(where: { $0.textView === source }) else { return }
        document.session.edit(source.string)
    }
    func undoManager(for view: NSTextView) -> UndoManager? {
        documents.first { $0.textView === view }?.undoManager
    }
    private func updateUI() {
        window?.title = session.file.map { "\($0.url.lastPathComponent) — Vavrio" } ?? "Vavrio — Open a File (⌘O)"
        window?.representedURL = session.file?.url
        window?.isDocumentEdited = documents.contains { $0.session.isDirty }
        textView?.isEditable = session.canEdit && !transitionActive
        openButton?.isEnabled = !busy && !transitionActive
        saveButton?.isEnabled = session.canSave && !transitionActive && !busy
        cancelButton?.isEnabled = session.isLoading
        statusLabel?.stringValue = active == nil ? "Open a folder or Markdown file to start." : session.status
        if readerVisible {
            if active != nil { reader.update(session.text) } else { reader.clear() }
        }
        for (index, view) in tabs.arrangedSubviews.enumerated() {
            guard let row = view as? NSStackView, let button = row.arrangedSubviews.first as? NSButton, documents.indices.contains(index) else { continue }
            let document = documents[index]
            button.title = (document.session.isDirty ? "● " : "") + document.url.lastPathComponent
            button.state = document === active ? .on : .off
            row.arrangedSubviews.forEach { ($0 as? NSButton)?.isEnabled = !busy && !transitionActive }
        }
    }
    @objc func openDocument(_ sender: Any?) {
        guard let window, !busy, !transitionActive else { return }
        transitionActive = true; updateUI()
        Task {
            let panel = NSOpenPanel()
            panel.title = "Open Markdown File"
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.message = "Open an existing UTF-8 .md file, up to 2 MiB."
            panel.canChooseFiles = true; panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            let response = await panel.beginSheetModal(for: window)
            panel.orderOut(nil)
            guard response == .OK, let url = panel.url else {
                transitionActive = false; updateUI(); return
            }
            transitionActive = false
            openURL(url)
        }
    }
    @objc func openFolder(_ sender: Any?) {
        guard let window, !transitionActive, !busy else { return }
        transitionActive = true; updateUI()
        Task {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            if await panel.beginSheetModal(for: window) == .OK, let url = panel.url {
                browser.open(url)
            }
            transitionActive = false; updateUI()
        }
    }
    @objc private func refreshFolder(_ sender: Any?) { browser.refresh() }
    func openURL(_ url: URL) {
        guard !transitionActive, !busy else { return }
        guard url.pathExtension.lowercased() == "md" else { return }
        let url = url.standardizedFileURL
        if let existing = documents.first(where: { $0.url == url }) { select(existing); return }
        let document = EditorDocument(url: url)
        documents.append(document)
        document.textView.delegate = self
        document.session.didChange = { [weak self] in self?.updateUI() }
        rebuildTabs()
        select(document)
        operationPending = true; updateUI()
        Task {
            if await document.session.open(url) {
                document.textView.string = document.session.text
                document.undoManager.removeAllActions()
            } else {
                await alert("Couldn’t Open File", document.session.status)
                remove(document)
            }
            operationPending = false
            updateUI()
        }
    }
    private func rebuildTabs() {
        for view in tabs.arrangedSubviews { tabs.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, document) in documents.enumerated() {
            let button = NSButton(title: document.url.lastPathComponent, target: self, action: #selector(selectTab(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = index; button.toolTip = document.url.path
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")!, target: self, action: #selector(closeTab(_:)))
            close.isBordered = false
            close.tag = index
            close.toolTip = "Close " + document.url.lastPathComponent
            close.setAccessibilityLabel("Close " + document.url.lastPathComponent)
            let row = NSStackView(views: [button, close])
            row.spacing = 2
            tabs.addArrangedSubview(row)
        }
        updateUI()
    }
    @objc func closeTab(_ sender: NSButton) {
        guard !busy, !transitionActive, documents.indices.contains(sender.tag) else { return }
        let document = documents[sender.tag]
        if !document.session.isDirty { remove(document); return }
        select(document)
        closeDocument(sender)
    }
    @objc func toggleReader(_ sender: Any?) {
        readerVisible.toggle()
        reader.view.isHidden = !readerVisible
        if !readerVisible { reader.suspend() }
        readerButton?.state = readerVisible ? .on : .off
        documentSplit.adjustSubviews()
        if readerVisible { documentSplit.setPosition(documentSplit.bounds.width / 2, ofDividerAt: 0) }
        updateUI()
    }
    @objc private func selectTab(_ sender: NSButton) {
        guard !transitionActive, !busy, documents.indices.contains(sender.tag) else { updateUI(); return }
        select(documents[sender.tag])
    }
    func select(_ document: EditorDocument) {
        active?.textView.breakUndoCoalescing()
        for view in editorHost.subviews { view.removeFromSuperview() }
        active = document; textView = document.textView
        browser.selectFile(document.url)
        let view = document.scrollView
        view.frame = editorHost.bounds
        view.autoresizingMask = [.width, .height]
        editorHost.addSubview(view)
        window?.makeFirstResponder(textView)
        updateUI()
    }
    private func remove(_ document: EditorDocument) {
        let wasActive = active === document
        documents.removeAll { $0 === document }
        if wasActive {
            document.scrollView.removeFromSuperview()
            active = nil; textView = nil
            browser.selectFile(nil)
            if let next = documents.last { select(next) }
        }
        rebuildTabs()
    }
    @objc func closeDocument(_ sender: Any?) {
        guard let document = active, !transitionActive, !busy else { return }
        transitionActive = true; updateUI()
        Task {
            if await confirmTransition() { remove(document) }
            transitionActive = false; updateUI()
        }
    }
    private func confirmAllDocuments() async -> Bool {
        for document in documents where document.session.isDirty {
            select(document)
            guard await confirmTransition() else { return false }
        }
        return true
    }
    @objc func saveDocument(_ sender: Any?) {
        guard session.canSave, !transitionActive, !busy else { return }
        operationPending = true; updateUI()
        Task {
            _ = await performSave()
            operationPending = false; updateUI()
        }
    }
    @objc private func cancelOpen(_ sender: Any?) { session.cancelLoading() }
    @objc func undoDocument(_ sender: Any?) {
        guard !transitionActive, let active else { return }
        active.undoManager.undo()
        active.session.edit(active.textView.string)
    }
    @objc func redoDocument(_ sender: Any?) {
        guard !transitionActive, let active else { return }
        active.undoManager.redo()
        active.session.edit(active.textView.string)
    }
    private func performSave() async -> Bool {
        guard let result = await session.save() else { return false }
        switch result {
        case .saved(_, let warning):
            if warning != nil { await alert("Saved — Cleanup Needed", session.status) }
        case .notWritten: await alert("Couldn’t Save File", session.status)
        case .uncertain: await alert("Save Outcome Is Uncertain", session.status)
        }
        return !session.isDirty
    }
    private func alert(_ title: String, _ message: String) async {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title; alert.informativeText = message
        _ = await alert.beginSheetModal(for: window)
    }
    private func confirmTransition() async -> Bool {
        guard let window, !session.isSaving else { return false }
        if session.isLoading { session.cancelLoading() }
        guard session.isDirty else { return true }
        if let decision, let active {
            switch await decision(active) {
            case .save: return await performSave()
            case .discard: return true
            case .cancel: return false
            }
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(session.file?.url.lastPathComponent ?? "this file")?"
        alert.informativeText = "Your changes will be lost if you discard them. Cancel keeps the document open."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].isEnabled = session.canSave
        let response = await alert.beginSheetModal(for: window)
        switch response {
        case .alertFirstButtonReturn: return await performSave()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        guard !transitionActive, !busy else { return false }
        transitionActive = true; updateUI()
        Task {
            if await confirmAllDocuments() {
                allowClose = true; allowTermination = true
                sender.performClose(nil)
            }
            transitionActive = false; updateUI()
        }
        return false
    }
    func requestApplicationTermination(reply: @escaping @MainActor (Bool) -> Void) -> NSApplication.TerminateReply {
        if allowTermination { return .terminateNow }
        guard !transitionActive, !busy else { return .terminateCancel }
        transitionActive = true; updateUI()
        Task {
            let shouldQuit = await confirmAllDocuments()
            allowTermination = shouldQuit
            transitionActive = false; updateUI()
            reply(shouldQuit)
        }
        return .terminateLater
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(closeDocument(_:)): active != nil && !busy && !transitionActive
        case #selector(openFolder(_:)), #selector(openDocument(_:)): !busy && !transitionActive
        case #selector(saveDocument(_:)): session.canSave && !transitionActive && !busy
        case #selector(undoDocument(_:)): editorUndoManager.canUndo && !transitionActive
        case #selector(redoDocument(_:)): editorUndoManager.canRedo && !transitionActive
        default: true
        }
    }
}
