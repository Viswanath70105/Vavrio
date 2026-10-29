import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var isOpeningFile = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vavrio — Open a File (⌘O)"
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)

        // Keep code-like text literal instead of applying prose substitutions.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        // Wrap to the viewport's width and let the document grow vertically.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        window.contentView = scrollView
        window.center()
        self.window = window
        self.textView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func openDocument(_ sender: Any?) {
        guard let window, !isOpeningFile else { return }
        isOpeningFile = true

        let panel = NSOpenPanel()
        panel.title = "Open a UTF-8 Text File"
        panel.prompt = "Open"
        panel.message = "View one UTF-8 code or text file, up to 2 MiB."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            panel.orderOut(nil)
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.isOpeningFile = false
                return
            }
            Task { await self.loadFile(at: url) }
        }
    }

    private func loadFile(at url: URL) async {
        // File I/O runs off the main actor; only one Open request is active.
        let result = await Task.detached(priority: .userInitiated) {
            Result { try TextFileReader.read(url) }
        }.value
        defer { isOpeningFile = false }

        guard let window, let textView else { return }
        switch result {
        case .success(let file):
            textView.string = file.text
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            window.title = "\(file.url.lastPathComponent) — Vavrio (Read Only)"
            window.representedURL = file.url
            window.makeFirstResponder(textView)
        case .failure(let error):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Open File"
            alert.informativeText = "\(url.lastPathComponent)\n\n\(error.localizedDescription)"
            _ = await alert.beginSheetModal(for: window)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openDocument(_:)) {
            return !isOpeningFile
        }
        return true
    }

    private func configureMenu() {
        let menuBar = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Vavrio")
        applicationMenu.addItem(withTitle: "Quit Vavrio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menuBar.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menuBar.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // Nil targets send these actions through the responder chain to the editor.
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menuBar.addItem(editItem)

        NSApplication.shared.mainMenu = menuBar
    }
}
