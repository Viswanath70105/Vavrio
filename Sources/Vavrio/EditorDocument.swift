import AppKit

/// Keeping a native editor per open document preserves selection, scrolling and undo.
@MainActor
final class EditorDocument {
    let id = UUID()
    private var openingURL: URL?
    let session: DocumentSession
    var url: URL? { session.file?.url ?? openingURL }
    var displayName: String {
        if let url { return url.lastPathComponent }
        if case .untitled(let name) = session.origin { return name }
        return "Opening…"
    }
    func finishOpening() { openingURL = nil }
    let undoManager = UndoManager()
    let scrollView = NSScrollView()
    let textView: NSTextView

    init(url: URL? = nil, untitledName: String? = nil) {
        openingURL = url
        session = DocumentSession(untitledName: untitledName)
        textView = NSTextView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
    }
}
