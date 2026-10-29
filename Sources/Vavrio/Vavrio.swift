import AppKit

@main
enum Vavrio {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = delegate

        // NSApplication's delegate is weak; keep it alive for the event loop.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
