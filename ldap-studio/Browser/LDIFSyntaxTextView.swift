//
//  LDIFSyntaxTextView.swift
//  ldap-studio
//
//  A syntax-highlighted plain-text editor for LDIF, wrapping NSTextView
//  (SwiftUI's TextEditor can't do coloured text). Line numbers in the
//  ruler, live re-highlight on every edit, and a faint red wash on lines
//  the parser rejected.
//

import AppKit
import SwiftUI

struct LDIFSyntaxTextView: NSViewRepresentable {
    @Binding var text: String
    var errorLines: Set<Int> = []

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.smartInsertDeleteEnabled = false
        textView.font = Theme.font
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.textContainer?.lineFragmentPadding = 6
        textView.string = text

        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        let ruler = LineNumberRuler(scrollView: scroll, textView: textView)
        scroll.verticalRulerView = ruler

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.errorLines = errorLines
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        var needsHighlight = false

        if textView.string != text {
            let ranges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = ranges
            needsHighlight = true
        }
        if context.coordinator.errorLines != errorLines {
            context.coordinator.errorLines = errorLines
            needsHighlight = true
        }
        if needsHighlight {
            context.coordinator.highlight()
            context.coordinator.ruler?.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: LDIFSyntaxTextView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        var errorLines: Set<Int> = []

        init(_ parent: LDIFSyntaxTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            highlight()
            ruler?.needsDisplay = true
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }
            LDIFHighlighter.apply(to: storage, errorLines: errorLines)
        }
    }
}

// MARK: - Tokeniser

enum LDIFHighlighter {
    static func apply(to storage: NSTextStorage, errorLines: Set<Int>) {
        let string = storage.string as NSString
        let whole = NSRange(location: 0, length: string.length)

        storage.beginEditing()
        storage.setAttributes([
            .font: Theme.font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Theme.paragraph,
        ], range: whole)

        var lineNumber = 0
        string.enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            lineNumber += 1
            style(line: lineRange, number: lineNumber, in: string, storage: storage, errorLines: errorLines)
        }
        storage.endEditing()
    }

    private static func style(line range: NSRange, number: Int, in string: NSString,
                              storage: NSTextStorage, errorLines: Set<Int>) {
            if errorLines.contains(number) {
                storage.addAttribute(.backgroundColor, value: Theme.errorWash, range: range)
            }

            let line = string.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }

            if line.hasPrefix("#") {
                storage.addAttribute(.foregroundColor, value: Theme.comment, range: range)
                return
            }
            if trimmed == "-" {
                storage.addAttribute(.foregroundColor, value: Theme.separator, range: range)
                return
            }
            if line.hasPrefix(" ") { // folded continuation line
                storage.addAttribute(.foregroundColor, value: Theme.value, range: range)
                return
            }
            if line.lowercased().hasPrefix("version:") {
                storage.addAttribute(.foregroundColor, value: Theme.comment, range: range)
                return
            }
            guard let colon = line.firstIndex(of: ":") else { return }

            let name = String(line[line.startIndex..<colon])
            let nameLength = (name as NSString).length
            var attrFont = Theme.font
            let attrColor: NSColor
            switch name.lowercased() {
            case "dn":
                attrColor = Theme.dn
                attrFont = Theme.boldFont
            case "changetype":
                attrColor = Theme.keyword
                attrFont = Theme.boldFont
            case "add", "delete", "replace", "newrdn", "deleteoldrdn",
                 "newsuperior", "modrdn", "moddn":
                attrColor = Theme.keyword
                attrFont = Theme.semiboldFont
            case "objectclass":
                attrColor = Theme.objectClass
            default:
                attrColor = Theme.attribute
            }
            storage.addAttributes([.foregroundColor: attrColor, .font: attrFont],
                                  range: NSRange(location: range.location, length: nameLength))

            // ':' or '::'
            var punctuationLength = 1
            let afterColon = line.index(after: colon)
            let isBase64 = afterColon < line.endIndex && line[afterColon] == ":"
            if isBase64 { punctuationLength = 2 }
            storage.addAttribute(.foregroundColor, value: Theme.punctuation,
                                 range: NSRange(location: range.location + nameLength,
                                                length: punctuationLength))

            let valueOffset = nameLength + punctuationLength
            if valueOffset < range.length {
                storage.addAttribute(.foregroundColor,
                                     value: isBase64 ? Theme.base64 : Theme.value,
                                     range: NSRange(location: range.location + valueOffset,
                                                    length: range.length - valueOffset))
            }
    }
}

// MARK: - Palette

private enum Theme {
    static let size: CGFloat = 12.5
    static let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    static let semiboldFont = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)

    static let paragraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        style.lineBreakMode = .byWordWrapping
        return style
    }()

    static let dn = NSColor.systemTeal
    static let keyword = NSColor.systemPurple
    static let objectClass = NSColor.systemIndigo
    static let attribute = NSColor.systemBlue
    static let value = NSColor.labelColor
    static let base64 = NSColor.systemGreen
    static let comment = NSColor.tertiaryLabelColor
    static let separator = NSColor.quaternaryLabelColor
    static let punctuation = NSColor.secondaryLabelColor
    static let errorWash = NSColor.systemRed.withAlphaComponent(0.13)
}

// MARK: - Line-number ruler

final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46

        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedraw),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedraw),
            name: NSText.didChangeNotification, object: textView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func needsRedraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: bounds.maxX - 0.5, y: bounds.minY, width: 0.5, height: bounds.height).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let inset = textView.textContainerInset.height
        let visibleRect = textView.visibleRect
        let string = textView.string as NSString

        if string.length == 0 {
            ("1" as NSString).draw(at: NSPoint(x: ruleThickness - 16, y: inset - visibleRect.minY),
                                   withAttributes: attributes)
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let firstCharIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)

        var lineNumber = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: firstCharIndex),
                                   options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var fragmentRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex,
                                                              effectiveRange: &fragmentRange)
            let charIndex = layoutManager.characterIndexForGlyph(at: fragmentRange.location)
            let lineStart = string.lineRange(for: NSRange(location: charIndex, length: 0)).location

            if charIndex == lineStart {
                let numberString = "\(lineNumber)" as NSString
                let numberSize = numberString.size(withAttributes: attributes)
                let y = fragmentRect.minY + inset - visibleRect.minY
                    + (fragmentRect.height - numberSize.height) / 2
                numberString.draw(at: NSPoint(x: ruleThickness - numberSize.width - 8, y: y),
                                  withAttributes: attributes)
                lineNumber += 1
            }
            glyphIndex = NSMaxRange(fragmentRange)
        }
    }
}
