import AppKit

/// A native reading view for common Markdown; never executes HTML or loads remote media.
@MainActor
final class MarkdownReader {
    let view = NSScrollView()
    let textView = NSTextView(frame: .zero)
    private var work: Task<Void, Never>?
    private var lastText: String?

    init() {
        view.hasVerticalScroller = true
        view.autohidesScrollers = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        view.documentView = textView
    }
    func update(_ source: String) {
        guard source != lastText else { return }
        lastText = source
        work?.cancel()
        work = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self else { return }
            let origin = view.contentView.bounds.origin
            let limited = String(source.prefix(200_000))
            let suffix = source.count > 200_000 ? "\n\nReader limited to the first 200,000 characters. The source editor contains the complete file." : ""
            textView.textStorage?.setAttributedString(Self.render(limited + suffix))
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            view.contentView.scroll(to: origin)
            view.reflectScrolledClipView(view.contentView)
        }
    }
    func suspend() { work?.cancel(); lastText = nil }
    func clear() {
        work?.cancel(); lastText = nil
        textView.string = "Open a Markdown file to read it here."
    }
    static func render(_ source: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var fence: String?
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = String(line.prefix(3))
                if fence == nil { fence = marker; continue }
                if fence == marker { fence = nil; continue }
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 8
            paragraph.lineSpacing = 3
            if fence != nil {
                output.append(NSAttributedString(string: raw + "\n", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor,
                    .paragraphStyle: paragraph]))
                continue
            }
            var body = line
            var font = NSFont.systemFont(ofSize: 15)
            var color = NSColor.labelColor
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
                body = String(line.dropFirst(hashes + 1))
                font = .systemFont(ofSize: CGFloat(30 - hashes * 2), weight: .bold)
                paragraph.paragraphSpacingBefore = 12
            } else if line.hasPrefix("> ") {
                body = String(line.dropFirst(2)); color = .secondaryLabelColor
                paragraph.headIndent = 16; paragraph.firstLineHeadIndent = 16
            } else if ["- ", "* ", "+ "].contains(where: { line.hasPrefix($0) }) {
                body = "• " + line.dropFirst(2)
                body = body.replacingOccurrences(of: "• [ ] ", with: "☐ ")
                    .replacingOccurrences(of: "• [x] ", with: "☑ ")
                paragraph.headIndent = 18
            } else if ["---", "***", "___"].contains(line) {
                body = "────────────────────────"; color = .separatorColor
            } else if line.hasPrefix("|") {
                // Keep table columns legible without introducing an HTML engine.
                font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            }
            let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if let inline = try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                for run in inline.runs {
                    var attributes = base
                    var runFont = font
                    if let intent = run.inlinePresentationIntent {
                        if intent.contains(.code) {
                            runFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
                            attributes[.backgroundColor] = NSColor.quaternaryLabelColor
                        }
                        if intent.contains(.stronglyEmphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask) }
                        if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
                        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    }
                    attributes[.font] = runFont
                    if let link = run.link, ["https", "http"].contains(link.scheme?.lowercased() ?? "") { attributes[.link] = link }
                    output.append(NSAttributedString(string: String(inline[run.range].characters), attributes: attributes))
                }
                output.append(NSAttributedString(string: "\n", attributes: base))
            } else { output.append(NSAttributedString(string: body + "\n", attributes: base)) }
        }
        return output
    }
}
