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
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(EditorWindowController.openDocument(_:)), keyEquivalent: "o")
        openItem.target = editor
        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveDocument(_:)), keyEquivalent: "s")
        saveItem.target = editor
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
        editItem.submenu = editMenu; menuBar.addItem(editItem)
        NSApplication.shared.mainMenu = menuBar
    }
}
