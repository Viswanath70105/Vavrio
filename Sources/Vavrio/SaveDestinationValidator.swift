import AppKit

/// Panel validation is advisory; the creation writer independently refuses collisions.
@MainActor
final class SaveDestinationValidator: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, validate url: URL) throws {
        guard let panel = sender as? NSSavePanel else { return }
        let enteredExtension = (panel.nameFieldStringValue as NSString).pathExtension
        guard (enteredExtension.isEmpty || enteredExtension.lowercased() == "md"),
              url.pathExtension.lowercased() == "md" else {
            throw FileCreationFailure.invalidDestination
        }
        try TextFileCreator.requireAbsent(url)
    }
}
