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
    private enum OperationKind { case open, reload, save }
    private var operation: (kind: OperationKind, document: EditorDocument)?
    var busy: Bool { operation != nil || documents.contains { $0.session.isWorking } }
    var transitioning: Bool { transitionActive }
    private var canStartOperation: Bool { !busy && !transitionActive }
    private var canSelectLoaded: Bool { !transitionActive && operation?.kind != .save }
    private var readDocument: EditorDocument? {
        guard let operation, operation.kind != .save else { return nil }
        return operation.document
    }
    private var lastReadStatus: String?
    private var refreshButton: NSButton?
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
    private let read: @Sendable (URL) throws -> TextFile
    private let readTimeout: Duration
    private let reloadDecision: (@MainActor (EditorDocument) async -> Bool)?
    private let presentAlert: (@MainActor (String, String) async -> Void)?
    init(decision: (@MainActor (EditorDocument) async -> UnsavedDecision)? = nil,
         read: @escaping @Sendable (URL) throws -> TextFile = TextFileReader.read,
         readTimeout: Duration = .seconds(10),
         reloadDecision: (@MainActor (EditorDocument) async -> Bool)? = nil,
         presentAlert: (@MainActor (String, String) async -> Void)? = nil) {
        self.decision = decision
        self.read = read; self.readTimeout = readTimeout
        self.reloadDecision = reloadDecision; self.presentAlert = presentAlert
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
        let cancelButton = NSButton(title: "Cancel Read", target: self, action: #selector(cancelRead(_:)))
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshFolder(_:)))
        refreshButton = refresh
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
        for document in documents { document.textView.isEditable = document.session.canEdit && !transitionActive }
        openButton?.isEnabled = canStartOperation
        refreshButton?.isEnabled = canStartOperation
        readerButton?.isEnabled = !transitionActive
        saveButton?.isEnabled = session.canSave && !transitionActive && !busy
        cancelButton?.isEnabled = readDocument?.session.isLoading == true && !transitionActive
        if let document = readDocument {
            statusLabel?.stringValue = "\(document.url.lastPathComponent): \(document.session.status)"
        } else {
            statusLabel?.stringValue = lastReadStatus ?? (active == nil ? "Open a folder or Markdown file to start." : session.status)
        }
        statusLabel?.toolTip = statusLabel?.stringValue
        if readerVisible {
            if active != nil { reader.update(session.text) } else { reader.clear() }
        }
        for (index, view) in tabs.arrangedSubviews.enumerated() {
            guard let row = view as? NSStackView, let button = row.arrangedSubviews.first as? NSButton, documents.indices.contains(index) else { continue }
            let document = documents[index]
            button.title = (document.session.isDirty ? "● " : "") + document.url.lastPathComponent
            button.state = document === active ? .on : .off
            button.isEnabled = canSelectLoaded && document.session.file != nil
            (row.arrangedSubviews.last as? NSButton)?.isEnabled = canStartOperation
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
    @objc func refreshFolder(_ sender: Any?) {
        guard canStartOperation else { return }
        browser.refresh()
    }
    func openURL(_ url: URL) {
        guard !transitionActive, url.pathExtension.lowercased() == "md" else { return }
        let url = url.standardizedFileURL
        if let existing = documents.first(where: { $0.url == url }) {
            select(existing); return
        }
        guard canStartOperation else { return }
        let previous = active
        let document = EditorDocument(url: url)
        operation = (.open, document)
        documents.append(document)
        document.textView.delegate = self
        document.session.didChange = { [weak self] in self?.updateUI() }
        rebuildTabs()
        show(document)
        beginRead(document, kind: .open, previous: previous)
    }
    private func beginRead(_ document: EditorDocument, kind: DocumentSession.ReadKind,
                           previous: EditorDocument? = nil) {
        lastReadStatus = nil
        updateUI()
        Task {
            let outcome = await document.session.open(document.url, kind: kind,
                                                       timeout: readTimeout, read: read)
            if outcome == .loaded {
                document.textView.string = document.session.text
                document.undoManager.removeAllActions()
                document.textView.setSelectedRange(NSRange(location: 0, length: 0))
                document.scrollView.contentView.scroll(to: .zero)
                document.scrollView.reflectScrolledClipView(document.scrollView.contentView)
            } else {
                lastReadStatus = "\(document.url.lastPathComponent): \(document.session.status)"
                if outcome == .failed {
                    await alert(kind == .reload ? "Couldn’t Reload File" : "Couldn’t Open File",
                                "\(document.url.path)\n\(document.session.status)")
                }
                if kind == .open { remove(document, preferred: previous) }
            }
            operation = nil
            updateUI()
        }
    }
    @objc func reloadDocument(_ sender: Any?) {
        guard canStartOperation, let document = active, document.session.file != nil else { return }
        if !document.session.isDirty {
            operation = (.reload, document)
            beginRead(document, kind: .reload)
            return
        }
        transitionActive = true; updateUI()
        Task {
            let approved: Bool
            if let reloadDecision { approved = await reloadDecision(document) }
            else if let window {
                let prompt = NSAlert()
                prompt.messageText = "Reload \(document.url.lastPathComponent) from disk?"
                prompt.informativeText = "A successful reload replaces your editor contents and clears undo history. Copy any edits you want to retain first."
                    + (document.session.uncertainSave ? " The previous save outcome is uncertain; the disk may already contain the attempted save." : "")
                prompt.addButton(withTitle: "Cancel")
                prompt.addButton(withTitle: "Discard Edits and Reload")
                prompt.buttons[0].keyEquivalent = "\r"
                prompt.buttons[1].hasDestructiveAction = true
                approved = await prompt.beginSheetModal(for: window) == .alertSecondButtonReturn
            } else { approved = false }
            transitionActive = false
            if approved {
                operation = (.reload, document)
                beginRead(document, kind: .reload)
            } else { updateUI() }
        }
    }
    @objc func revealRecoveryFolder(_ sender: Any?) {
        guard canStartOperation, let directory = active?.session.recoveryDirectory else { return }
        transitionActive = true; updateUI()
        Task {
            let available = await Task.detached {
                (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.value
            if available { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
            else { await alert("Recovery Folder Unavailable", "The recorded folder is unavailable: \(directory.path). It has not been recreated or deleted.") }
            transitionActive = false; updateUI()
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
        guard !transitionActive else { return }
        readerVisible.toggle()
        reader.view.isHidden = !readerVisible
        if !readerVisible { reader.suspend() }
        readerButton?.state = readerVisible ? .on : .off
        documentSplit.adjustSubviews()
        if readerVisible { documentSplit.setPosition(documentSplit.bounds.width / 2, ofDividerAt: 0) }
        updateUI()
    }
    @objc private func selectTab(_ sender: NSButton) {
        guard documents.indices.contains(sender.tag) else { updateUI(); return }
        select(documents[sender.tag])
    }
    func select(_ document: EditorDocument) {
        guard canSelectLoaded, document.session.file != nil,
              documents.contains(where: { $0 === document }) else { return }
        lastReadStatus = nil
        show(document)
    }
    private func show(_ document: EditorDocument) {
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
    private func remove(_ document: EditorDocument, preferred: EditorDocument? = nil) {
        let wasActive = active === document
        documents.removeAll { $0 === document }
        if wasActive {
            document.scrollView.removeFromSuperview()
            active = nil; textView = nil
            browser.selectFile(nil)
            if let preferred, documents.contains(where: { $0 === preferred }), preferred.session.file != nil {
                show(preferred)
            } else if let next = documents.last(where: { $0.session.file != nil }) { show(next) }
        }
        rebuildTabs()
    }
    @objc func closeDocument(_ sender: Any?) {
        guard let document = active, !transitionActive, !busy else { return }
        transitionActive = true; updateUI()
        Task {
            if await confirmTransition(document) { remove(document) }
            transitionActive = false; updateUI()
        }
    }
    private func confirmAllDocuments() async -> Bool {
        for document in documents where document.session.isDirty {
            show(document)
            guard await confirmTransition(document) else { return false }
        }
        return true
    }
    @objc func saveDocument(_ sender: Any?) {
        guard canStartOperation, let document = active, document.session.canSave else { return }
        operation = (.save, document); lastReadStatus = nil; updateUI()
        Task {
            _ = await performSave(document)
            operation = nil; updateUI()
        }
    }
    @objc func cancelRead(_ sender: Any?) {
        guard !transitionActive else { return }
        readDocument?.session.cancelLoading()
    }
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
    private func performSave(_ document: EditorDocument) async -> Bool {
        let session = document.session
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
        let alreadyTransitioning = transitionActive
        transitionActive = true; updateUI()
        defer { transitionActive = alreadyTransitioning; updateUI() }
        if let presentAlert { await presentAlert(title, message); return }
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title; alert.informativeText = message
        _ = await alert.beginSheetModal(for: window)
    }
    private func confirmTransition(_ document: EditorDocument) async -> Bool {
        let session = document.session
        guard let window, !session.isSaving else { return false }
        if session.isLoading { session.cancelLoading() }
        guard session.isDirty else { return true }
        if let decision {
            switch await decision(document) {
            case .save: return await performSave(document)
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
        case .alertFirstButtonReturn: return await performSave(document)
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
        case #selector(openFolder(_:)), #selector(openDocument(_:)), #selector(refreshFolder(_:)): canStartOperation
        case #selector(reloadDocument(_:)): canStartOperation && session.file != nil
        case #selector(revealRecoveryFolder(_:)): canStartOperation && session.recoveryDirectory != nil
        case #selector(cancelRead(_:)): !transitionActive && readDocument?.session.isLoading == true
        case #selector(toggleReader(_:)): !transitionActive
        case #selector(saveDocument(_:)): session.canSave && !transitionActive && !busy
        case #selector(undoDocument(_:)): editorUndoManager.canUndo && !transitionActive
        case #selector(redoDocument(_:)): editorUndoManager.canRedo && !transitionActive
        default: true
        }
    }
}
