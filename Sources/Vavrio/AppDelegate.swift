import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate, NSTextViewDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?
    private let session = DocumentSession()
    private let editorUndoManager = UndoManager()
    private var openButton: NSButton?
    private var saveButton: NSButton?
    private var cancelButton: NSButton?
    private var statusLabel: NSTextField?
    private var transitionActive = false
    private var allowClose = false
    private var allowTermination = false
    private var applyingText = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // Match the initial viewport: a fixed starting width becomes surplus
        // width when Auto Layout later grows the initially empty scroll view.
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = self
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        let container = NSView()
        let openButton = NSButton(title: "Open…", target: self, action: #selector(openDocument(_:)))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveDocument(_:)))
        let cancelButton = NSButton(title: "Cancel Open", target: self, action: #selector(cancelOpen(_:)))
        let buttons = NSStackView(views: [openButton, saveButton, cancelButton])
        buttons.spacing = 8
        let status = NSTextField(labelWithString: session.status)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        for view in [buttons, scrollView, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            buttons.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        window.contentView = container
        self.window = window; self.textView = textView
        self.openButton = openButton; self.saveButton = saveButton
        self.cancelButton = cancelButton; self.statusLabel = status
        session.didChange = { [weak self] in self?.updateUI() }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        updateUI()
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { editorUndoManager }
    func textDidChange(_ notification: Notification) {
        guard !applyingText, let textView else { return }
        session.edit(textView.string)
    }
    private func updateUI() {
        window?.title = session.file.map { "\($0.url.lastPathComponent) — Vavrio" } ?? "Vavrio — Open a File (⌘O)"
        window?.representedURL = session.file?.url
        window?.isDocumentEdited = session.isDirty
        textView?.isEditable = session.canEdit
        openButton?.isEnabled = !session.isWorking && !transitionActive
        saveButton?.isEnabled = session.canSave && !transitionActive
        cancelButton?.isEnabled = session.isLoading
        statusLabel?.stringValue = session.status
    }
    @objc private func openDocument(_ sender: Any?) {
        guard let window, !session.isWorking, !transitionActive else { return }
        transitionActive = true; updateUI()
        Task {
            let panel = NSOpenPanel()
            panel.title = "Open a UTF-8 Text File"
            panel.message = "Open one UTF-8 code or text file, up to 2 MiB."
            panel.canChooseFiles = true; panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            let response = await panel.beginSheetModal(for: window)
            panel.orderOut(nil)
            guard response == .OK, let url = panel.url else {
                transitionActive = false; updateUI(); return
            }
            guard await confirmTransition() else { transitionActive = false; updateUI(); return }
            transitionActive = false
            let opened = await session.open(url)
            if opened, let textView {
                applyingText = true
                textView.string = session.text
                editorUndoManager.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
                applyingText = false
                window.makeFirstResponder(textView)
            } else if session.status.hasPrefix("Couldn’t open") {
                await alert("Couldn’t Open File", session.status)
            }
            updateUI()
        }
    }
    @objc private func saveDocument(_ sender: Any?) {
        guard session.canSave, !transitionActive else { return }
        Task { _ = await performSave() }
    }
    @objc private func cancelOpen(_ sender: Any?) { session.cancelLoading() }
    @objc private func undoDocument(_ sender: Any?) { if !transitionActive { editorUndoManager.undo() } }
    @objc private func redoDocument(_ sender: Any?) { if !transitionActive { editorUndoManager.redo() } }
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
        guard !transitionActive, !session.isSaving else { return false }
        transitionActive = true; updateUI()
        Task {
            if await confirmTransition() {
                allowClose = true; allowTermination = true
                sender.performClose(nil)
            }
            transitionActive = false; updateUI()
        }
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTermination { return .terminateNow }
        guard !transitionActive, !session.isSaving else { return .terminateCancel }
        transitionActive = true; updateUI()
        Task {
            let shouldQuit = await confirmTransition()
            allowTermination = shouldQuit
            transitionActive = false; updateUI()
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openDocument(_:)): !session.isWorking && !transitionActive
        case #selector(saveDocument(_:)): session.canSave && !transitionActive
        case #selector(undoDocument(_:)): editorUndoManager.canUndo && !transitionActive
        case #selector(redoDocument(_:)): editorUndoManager.canRedo && !transitionActive
        default: true
        }
    }
    private func configureMenu() {
        let menuBar = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Vavrio")
        applicationMenu.addItem(withTitle: "Quit Vavrio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu; menuBar.addItem(applicationItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        saveItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu; menuBar.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undo = editMenu.addItem(withTitle: "Undo", action: #selector(undoDocument(_:)), keyEquivalent: "z")
        undo.target = self
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(redoDocument(_:)), keyEquivalent: "z")
        redo.target = self; redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu; menuBar.addItem(editItem)
        NSApplication.shared.mainMenu = menuBar
    }
}
