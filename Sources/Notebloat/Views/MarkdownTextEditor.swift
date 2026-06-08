import SwiftUI
import AppKit

/// Plain-text editor with optional non-destructive Markdown live preview.
/// Inactive lines are styled while selected lines always show their source.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let rendersMarkdown: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.layoutManager?.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.refreshAppearance()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            context.coordinator.isUpdatingText = true
            textView.string = text
            textView.setSelectedRange(
                NSRange(
                    location: min(selection.location, (text as NSString).length),
                    length: 0
                )
            )
            context.coordinator.isUpdatingText = false
        }
        context.coordinator.refreshAppearance()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: MarkdownTextEditor
        weak var textView: NSTextView?
        var isUpdatingText = false
        var isUpdatingAppearance = false

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingText, !isUpdatingAppearance else { return }
            parent.text = textView.string
            refreshAppearance()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            refreshAppearance()
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes: UnsafePointer<Int>,
            font: NSFont,
            forGlyphRange glyphRange: NSRange
        ) -> Int {
            guard let textStorage = layoutManager.textStorage else { return 0 }
            var replacementGlyphs = Array(
                UnsafeBufferPointer(start: glyphs, count: glyphRange.length)
            )
            var replacedAnyGlyph = false

            for offset in 0..<glyphRange.length {
                let characterIndex = characterIndexes[offset]
                guard characterIndex < textStorage.length,
                      let symbol = textStorage.attribute(
                          .notebloatListMarker,
                          at: characterIndex,
                          effectiveRange: nil
                      ) as? String,
                      let character = symbol.utf16.first
                else { continue }

                var utf16Character = character
                var replacementGlyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(
                    font as CTFont,
                    &utf16Character,
                    &replacementGlyph,
                    1
                ) {
                    replacementGlyphs[offset] = replacementGlyph
                    replacedAnyGlyph = true
                }
            }

            guard replacedAnyGlyph else { return 0 }
            layoutManager.setGlyphs(
                replacementGlyphs,
                properties: properties,
                characterIndexes: characterIndexes,
                font: font,
                forGlyphRange: glyphRange
            )
            return glyphRange.length
        }

        func refreshAppearance() {
            guard let textView, let textStorage = textView.textStorage else { return }
            let font = NSFont.systemFont(ofSize: parent.fontSize)
            textView.insertionPointColor = .textColor

            let text = textView.string as NSString
            let activeRanges = textView.selectedRanges.compactMap { value -> NSRange? in
                let selection = value.rangeValue
                guard selection.location <= text.length else { return nil }
                return text.lineRange(for: selection)
            }
            isUpdatingAppearance = true
            MarkdownStyler.apply(
                to: textStorage,
                baseFont: font,
                activeLineRanges: activeRanges,
                enabled: parent.rendersMarkdown
            )
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.textColor
            ]
            isUpdatingAppearance = false
        }
    }
}
