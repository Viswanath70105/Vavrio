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
    private(set) var navigationPalette: NavigationPalette?
    private var scanWorker: Task<WorkspaceFileScan, Never>?
    private var scanToken: UUID?
    private let scanFiles: @Sendable (URL) -> WorkspaceFileScan
    private var allowClose = false
    private var allowTermination = false

    enum UnsavedDecision { case save, discard, cancel }
    private let decision: (@MainActor (EditorDocument) async -> UnsavedDecision)?
    private let read: @Sendable (URL) throws -> TextFile
    private let readTimeout: Duration
    private let reloadDecision: (@MainActor (EditorDocument) async -> Bool)?
    private var untitledCounter = 0
    private let chooseDestination: (@MainActor (EditorDocument) async -> URL?)?
    private let createFile: @Sendable (URL, String, Bool) async -> FileCreationResult
    private let presentAlert: (@MainActor (String, String) async -> Void)?
    init(decision: (@MainActor (EditorDocument) async -> UnsavedDecision)? = nil,
         read: @escaping @Sendable (URL) throws -> TextFile = TextFileReader.read,
         readTimeout: Duration = .seconds(10),
         reloadDecision: (@MainActor (EditorDocument) async -> Bool)? = nil,
         presentAlert: (@MainActor (String, String) async -> Void)? = nil,
         chooseDestination: (@MainActor (EditorDocument) async -> URL?)? = nil,
         scanFiles: @escaping @Sendable (URL) -> WorkspaceFileScan = { WorkspaceNavigation.scan($0) },
         createFile: @escaping @Sendable (URL, String, Bool) async -> FileCreationResult = {
             await TextFileCreator.create($0, text: $1, hasUTF8BOM: $2)
         }) {
        self.decision = decision
        self.scanFiles = scanFiles
        self.chooseDestination = chooseDestination; self.createFile = createFile
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
        window?.title = active.map { "\($0.displayName) — Vavrio" } ?? "Vavrio — Open a File (⌘O)"
        window?.representedURL = session.file?.url
        window?.isDocumentEdited = documents.contains { $0.session.isDirty }
        for document in documents { document.textView.isEditable = document.session.canEdit && !transitionActive }
        openButton?.isEnabled = canStartOperation
        refreshButton?.isEnabled = canStartOperation && browser.rootURL != nil
        readerButton?.isEnabled = !transitionActive
        saveButton?.isEnabled = session.canInvokeSave && !transitionActive && !busy
        cancelButton?.isEnabled = readDocument?.session.isLoading == true && !transitionActive
        if let document = readDocument {
            statusLabel?.stringValue = "\(document.displayName): \(document.session.status)"
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
            button.title = (document.session.isDirty ? "● " : "") + document.displayName
            button.state = document === active ? .on : .off
            button.toolTip = document.url?.path ?? document.displayName
            (row.arrangedSubviews.last as? NSButton)?.toolTip = "Close " + document.displayName
            (row.arrangedSubviews.last as? NSButton)?.setAccessibilityLabel("Close " + document.displayName)
            button.isEnabled = canSelectLoaded && document.session.canEdit
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
            let response = await panel.beginSheetModal(for: window)
            panel.orderOut(nil)
            transitionActive = false
            if response == .OK, let url = panel.url { openWorkspace(url) }
            updateUI()
        }
    }
    func openWorkspace(_ url: URL) {
        guard canStartOperation else { return }
        browser.open(url)
        updateUI()
    }
    @objc func refreshFolder(_ sender: Any?) {
        guard canStartOperation, browser.rootURL != nil else { return }
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
        guard let url = document.url else { operation = nil; updateUI(); return }
        Task {
            let outcome = await document.session.open(url, kind: kind,
                                                       timeout: readTimeout, read: read)
            if outcome == .loaded {
                document.finishOpening()
                document.textView.string = document.session.text
                document.undoManager.removeAllActions()
                document.textView.setSelectedRange(NSRange(location: 0, length: 0))
                document.scrollView.contentView.scroll(to: .zero)
                document.scrollView.reflectScrolledClipView(document.scrollView.contentView)
            } else {
                lastReadStatus = "\(document.displayName): \(document.session.status)"
                if outcome == .failed {
                    await alert(kind == .reload ? "Couldn’t Reload File" : "Couldn’t Open File",
                                "\(document.url?.path ?? document.displayName)\n\(document.session.status)")
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
                prompt.messageText = "Reload \(document.displayName) from disk?"
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
            let button = NSButton(title: document.displayName, target: self, action: #selector(selectTab(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = index; button.toolTip = document.url?.path ?? document.displayName
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")!, target: self, action: #selector(closeTab(_:)))
            close.isBordered = false
            close.tag = index
            close.toolTip = "Close " + document.displayName
            close.setAccessibilityLabel("Close " + document.displayName)
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
        guard canSelectLoaded, document.session.canEdit,
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
            if let preferred, documents.contains(where: { $0 === preferred }), preferred.session.canEdit {
                show(preferred)
            } else if let next = documents.last(where: { $0.session.canEdit }) { show(next) }
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
        guard canStartOperation, let document = active, document.session.canInvokeSave else { return }
        operation = (.save, document); lastReadStatus = nil; updateUI()
        Task {
            _ = await performSave(document)
            operation = nil; updateUI()
        }
    }
    @objc func newDocument(_ sender: Any?) {
        guard canStartOperation else { return }
        untitledCounter += 1
        let name = untitledCounter == 1 ? "Untitled" : "Untitled \(untitledCounter)"
        let document = EditorDocument(untitledName: name)
        documents.append(document)
        document.textView.delegate = self
        document.session.didChange = { [weak self] in self?.updateUI() }
        lastReadStatus = nil
        rebuildTabs(); show(document)
    }
    @objc func saveAsDocument(_ sender: Any?) {
        guard canStartOperation, let document = active, document.session.canSaveAs else { return }
        operation = (.save, document); lastReadStatus = nil; updateUI()
        Task {
            _ = await performSaveAs(document)
            operation = nil; updateUI()
        }
    }
    private func saveForClose(_ document: EditorDocument) async -> Bool {
        operation = (.save, document); updateUI()
        defer { operation = nil; updateUI() }
        if document.session.canInvokeSave { return await performSave(document) }
        return await performSaveAs(document)
    }
    private func performSaveAs(_ document: EditorDocument) async -> Bool {
        guard document.session.canSaveAs else { return false }
        let previousTransition = transitionActive
        transitionActive = true; updateUI()
        let selected: URL?
        if let chooseDestination { selected = await chooseDestination(document) }
        else if let window {
            let panel = NSSavePanel()
            let validator = SaveDestinationValidator()
            panel.delegate = validator
            panel.title = "Save Markdown As"
            panel.message = "Create a new private .md file. Existing files will not be replaced."
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.allowsOtherFileTypes = false
            panel.canCreateDirectories = false
            panel.nameFieldStringValue = document.session.file == nil ? document.displayName + ".md" : document.displayName
            panel.directoryURL = document.session.file?.url.deletingLastPathComponent() ?? browser.rootURL
            let response = await panel.beginSheetModal(for: window)
            panel.orderOut(nil)
            selected = response == .OK ? panel.url : nil
            withExtendedLifetime(validator) {}
        } else { selected = nil }
        guard let selected else {
            transitionActive = previousTransition; updateUI()
            return false
        }
        let occupied = documents.compactMap { $0.url } + [document.session.uncertainDestination].compactMap { $0 }
        let (destination, reserved) = await Task.detached {
            let destination = TextFileCreator.canonicalDestination(selected)
            return (destination, occupied.contains { TextFileCreator.canonicalDestination($0) == destination })
        }.value
        // Keep path resolution off the main actor and the panel transition exclusive.
        // A close/quit transition remains exclusive during writing; ordinary Save As permits editing.
        transitionActive = previousTransition; updateUI()
        guard !reserved else {
            await alert("Choose a New Destination", FileCreationFailure.reservedDestination.localizedDescription)
            return false
        }
        guard let result = await document.session.saveAs(destination, create: createFile) else { return false }
        switch result {
        case .created(_, let warning):
            document.finishOpening()
            browser.refresh(selecting: document.url)
            rebuildTabs()
            if warning != nil { await alert("Saved — Cleanup Needed", document.session.status) }
            return !document.session.isDirty
        case .notCreated:
            await alert("Couldn’t Create File", document.session.status)
        case .uncertain:
            await alert("Creation Outcome Is Uncertain", document.session.status)
        }
        return false
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
        if session.isUntitled { return await performSaveAs(document) }
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
            case .save: return await saveForClose(document)
            case .discard: return true
            case .cancel: return false
            }
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(document.displayName)?"
        alert.informativeText = "Your changes will be lost if you discard them. Cancel keeps the document open."
        alert.addButton(withTitle: session.canInvokeSave ? "Save" : "Save As…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].isEnabled = session.canSaveAs
        let response = await alert.beginSheetModal(for: window)
        alert.window.orderOut(nil)
        switch response {
        case .alertFirstButtonReturn: return await saveForClose(document)
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
    struct PaletteCommand {
        let title: String
        let detail: String
        let shortcut: String
        let action: Selector
    }
    var paletteCommands: [PaletteCommand] {
        [
            .init(title: "New Markdown Document", detail: "Create an untitled tab", shortcut: "⌘N", action: #selector(newDocument(_:))),
            .init(title: "Open File…", detail: "Open an existing Markdown document", shortcut: "⌘O", action: #selector(openDocument(_:))),
            .init(title: "Open Folder…", detail: "Choose a Markdown workspace", shortcut: "⇧⌘O", action: #selector(openFolder(_:))),
            .init(title: "Quick Open…", detail: "Search filenames and paths in the workspace", shortcut: "⌘P", action: #selector(quickOpen(_:))),
            .init(title: "Save", detail: "Save the active document", shortcut: "⌘S", action: #selector(saveDocument(_:))),
            .init(title: "Save As…", detail: "Create a new file and follow it in this tab", shortcut: "⇧⌘S", action: #selector(saveAsDocument(_:))),
            .init(title: "Reload from Disk", detail: "Reread the active file; confirm before discarding edits", shortcut: "", action: #selector(reloadDocument(_:))),
            .init(title: "Close Tab", detail: "Close the active tab with unsaved-edit protection", shortcut: "⌘W", action: #selector(closeDocument(_:))),
            .init(title: readerVisible ? "Hide Markdown Reader" : "Show Markdown Reader", detail: "Toggle rendered Markdown beside the source", shortcut: "", action: #selector(toggleReader(_:))),
            .init(title: "Refresh Explorer", detail: "Refresh folder entries without reloading documents", shortcut: "", action: #selector(refreshFolder(_:))),
            .init(title: "Reveal Recovery Folder", detail: "Locate the active document’s recorded recovery directory", shortcut: "", action: #selector(revealRecoveryFolder(_:))),
            .init(title: "Find in Document", detail: "Search the active editor with the native find bar", shortcut: "⌘F", action: #selector(findDocument(_:)))
        ]
    }
    func commandItems() -> [NavigationItem] {
        paletteCommands.map { command in
            let enabled = validateMenuItem(NSMenuItem(title: command.title, action: command.action, keyEquivalent: ""))
            return NavigationItem(id: NSStringFromSelector(command.action), title: command.title,
                                  detail: enabled ? command.detail : "Unavailable now · " + command.detail,
                                  shortcut: command.shortcut, enabled: enabled)
        }
    }
    @objc func commandPalette(_ sender: Any?) {
        guard canStartOperation else { return }
        let items = commandItems()
        showPalette(title: "Commands", placeholder: "Type a command…", items: items,
                    status: "Commands respect the same rules as menus.") { [weak self] id in
            guard let self, let command = paletteCommands.first(where: { NSStringFromSelector($0.action) == id }),
                  validateMenuItem(NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")) else { return }
            perform(command.action, with: nil)
        }
    }
    private func openDocumentItems() -> [NavigationItem] {
        documents.filter { $0.session.canEdit }.map {
            NavigationItem(id: "tab:" + $0.id.uuidString, title: $0.displayName,
                           detail: $0.url?.path ?? "Untitled document", shortcut: $0.session.isDirty ? "● Open" : "Open",
                           isOpenDocument: true)
        }
    }
    @objc func quickOpen(_ sender: Any?) {
        guard canStartOperation else { return }
        let root = browser.rootURL
        let palette = showPalette(title: "Quick Open", placeholder: "Search Markdown files by name or path…",
                                  items: openDocumentItems(),
                                  status: root == nil ? "Open a folder to search beyond your tabs." : "Searching workspace…") { [weak self] id in
            guard let self else { return }
            if id.hasPrefix("tab:"), let document = documents.first(where: { "tab:" + $0.id.uuidString == id }) {
                select(document)
            } else if id.hasPrefix("file:"), let url = URL(string: String(id.dropFirst(5))) { openURL(url) }
        }
        guard let root, let palette else { return }
        Task {
            // Cancellation is logical. Keep a blocked enumerator's slot until it returns.
            if let previous = scanWorker {
                palette.update(openDocumentItems(), status: "Waiting for the previous folder scan to finish; open tabs remain searchable.")
                _ = await previous.value
            }
            guard navigationPalette === palette else { return }
            let token = UUID()
            let scan = scanFiles
            let worker = Task.detached(priority: .userInitiated) { scan(root) }
            scanToken = token; scanWorker = worker
            let result = await worker.value
            if scanToken == token { scanWorker = nil; scanToken = nil }
            guard navigationPalette === palette else { return }
            let openPaths = Set(documents.compactMap { $0.url?.standardizedFileURL.path })
            let files = result.files.filter { !openPaths.contains($0.url.standardizedFileURL.path) }.map {
                NavigationItem(id: "file:" + $0.url.absoluteString, title: $0.url.lastPathComponent, detail: $0.relativePath)
            }
            var status = "\(result.files.count) Markdown files · \(root.lastPathComponent)"
            if result.truncated { status += " · Partial scan (limit reached or cancelled)" }
            if result.unreadableDirectories > 0 { status += " · \(result.unreadableDirectories) unreadable entries" }
            palette.update(openDocumentItems() + files, status: status)
        }
    }
    @discardableResult
    private func showPalette(title: String, placeholder: String, items: [NavigationItem], status: String,
                             choose: @escaping (String) -> Void) -> NavigationPalette? {
        guard let window else { return nil }
        let palette = NavigationPalette(title: title, placeholder: placeholder)
        navigationPalette = palette
        transitionActive = true; updateUI()
        palette.update(items, status: status)
        palette.onFinish = { [weak self, weak palette] id in
            guard let self, let palette, navigationPalette === palette else { return }
            scanWorker?.cancel()
            navigationPalette = nil
            transitionActive = false; updateUI()
            window.makeFirstResponder(textView)
            if let id { choose(id) }
        }
        palette.present(on: window)
        return palette
    }
    @objc func findDocument(_ sender: Any?) {
        guard !transitionActive, let active, active.session.canEdit else { return }
        window?.makeFirstResponder(active.textView)
        let item = NSMenuItem()
        item.tag = (sender as? NSMenuItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        active.textView.performFindPanelAction(item)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(commandPalette(_:)), #selector(quickOpen(_:)): canStartOperation
        case #selector(findDocument(_:)): !transitionActive && session.canEdit
        case #selector(closeDocument(_:)): active != nil && !busy && !transitionActive
        case #selector(refreshFolder(_:)): canStartOperation && browser.rootURL != nil
        case #selector(openFolder(_:)), #selector(openDocument(_:)), #selector(newDocument(_:)): canStartOperation
        case #selector(saveAsDocument(_:)): canStartOperation && session.canSaveAs
        case #selector(reloadDocument(_:)): canStartOperation && session.file != nil
        case #selector(revealRecoveryFolder(_:)): canStartOperation && session.recoveryDirectory != nil
        case #selector(cancelRead(_:)): !transitionActive && readDocument?.session.isLoading == true
        case #selector(toggleReader(_:)): !transitionActive
        case #selector(saveDocument(_:)): session.canInvokeSave && !transitionActive && !busy
        case #selector(undoDocument(_:)): editorUndoManager.canUndo && !transitionActive
        case #selector(redoDocument(_:)): editorUndoManager.canRedo && !transitionActive
        default: true
        }
    }
}
