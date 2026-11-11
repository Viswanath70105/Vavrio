import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let editor = EditorWindowController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        editor.showWindow(nil)
        NSApplication.shared.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editor.requestApplicationTermination { sender.reply(toApplicationShouldTerminate: $0) }
    }
    func configureMenu() {
        let menuBar = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Vavrio")
        applicationMenu.addItem(withTitle: "Quit Vavrio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu; menuBar.addItem(applicationItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let new = fileMenu.addItem(withTitle: "New", action: #selector(EditorWindowController.newDocument(_:)), keyEquivalent: "n")
        new.target = editor
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(EditorWindowController.openDocument(_:)), keyEquivalent: "o")
        openItem.target = editor
        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveDocument(_:)), keyEquivalent: "s")
        saveItem.target = editor
        let saveAs = fileMenu.addItem(withTitle: "Save As…", action: #selector(EditorWindowController.saveAsDocument(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        saveAs.target = editor
        let reload = fileMenu.addItem(withTitle: "Reload from Disk", action: #selector(EditorWindowController.reloadDocument(_:)), keyEquivalent: "")
        reload.target = editor
        let recovery = fileMenu.addItem(withTitle: "Reveal Recovery Folder", action: #selector(EditorWindowController.revealRecoveryFolder(_:)), keyEquivalent: "")
        recovery.target = editor
        fileMenu.addItem(.separator())
        let close = fileMenu.addItem(withTitle: "Close Tab", action: #selector(EditorWindowController.closeDocument(_:)), keyEquivalent: "w")
        close.target = editor
        let folder = fileMenu.addItem(withTitle: "Open Folder…", action: #selector(EditorWindowController.openFolder(_:)), keyEquivalent: "o")
        folder.keyEquivalentModifierMask = [.command, .shift]; folder.target = editor
        fileItem.submenu = fileMenu; menuBar.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undo = editMenu.addItem(withTitle: "Undo", action: #selector(EditorWindowController.undoDocument(_:)), keyEquivalent: "z")
        undo.target = editor
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(EditorWindowController.redoDocument(_:)), keyEquivalent: "z")
        redo.target = editor; redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        for (title, key, modifiers, action) in [
            ("Find…", "f", NSEvent.ModifierFlags.command, NSTextFinder.Action.showFindInterface),
            ("Find Next", "g", NSEvent.ModifierFlags.command, NSTextFinder.Action.nextMatch),
            ("Find Previous", "g", NSEvent.ModifierFlags([.command, .shift]), NSTextFinder.Action.previousMatch)
        ] {
            let item = editMenu.addItem(withTitle: title, action: #selector(EditorWindowController.findDocument(_:)), keyEquivalent: key)
            item.target = editor; item.tag = action.rawValue; item.keyEquivalentModifierMask = modifiers
        }
        editItem.submenu = editMenu; menuBar.addItem(editItem)
        let navigateItem = NSMenuItem()
        let navigate = NSMenu(title: "Navigate")
        let quick = navigate.addItem(withTitle: "Quick Open…", action: #selector(EditorWindowController.quickOpen(_:)), keyEquivalent: "p")
        quick.target = editor
        let commands = navigate.addItem(withTitle: "Command Palette…", action: #selector(EditorWindowController.commandPalette(_:)), keyEquivalent: "p")
        commands.target = editor; commands.keyEquivalentModifierMask = [.command, .shift]
        navigateItem.submenu = navigate; menuBar.addItem(navigateItem)
        NSApplication.shared.mainMenu = menuBar
    }
}
