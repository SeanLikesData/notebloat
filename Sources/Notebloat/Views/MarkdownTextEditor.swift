import SwiftUI
import AppKit

final class MarkdownLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }

        let characterRange = characterRange(
            forGlyphRange: glyphsToShow,
            actualGlyphRange: nil
        )
        textStorage.enumerateAttribute(
            .notebloatListMarker,
            in: characterRange,
            options: []
        ) { value, range, _ in
            guard let symbol = value as? String else { return }
            let glyphRange = self.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { return }

            let location = self.location(forGlyphAt: glyphRange.location)
            let lineFragment = self.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )
            let font = textStorage.attribute(
                .font,
                at: range.location,
                effectiveRange: nil
            ) as? NSFont ?? .systemFont(ofSize: NSFont.systemFontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.textColor
            ]
            let symbolSize = (symbol as NSString).size(withAttributes: attributes)
            let point = NSPoint(
                x: origin.x + lineFragment.minX + location.x,
                y: origin.y + lineFragment.minY
                    + ((lineFragment.height - symbolSize.height) / 2)
            )
            (symbol as NSString).draw(at: point, withAttributes: attributes)
        }
    }
}

final class MarkdownTextView: NSTextView {
    var onToggleCheckbox: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        let textContainerOrigin = self.textContainerOrigin
        let locationInTextContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else {
            super.mouseDown(with: event)
            return
        }
        
        let charIndex = layoutManager.characterIndex(
            for: locationInTextContainer,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        
        if charIndex < (self.textStorage?.length ?? 0) {
            if let value = self.textStorage?.attribute(.notebloatListMarker, at: charIndex, effectiveRange: nil) as? String,
               value == "☑" || value == "☐" {
                
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
                let boundingRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
                let lineFragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                
                let hitRect = NSRect(x: boundingRect.minX - 5, y: lineFragment.minY, width: boundingRect.width + 10, height: lineFragment.height)
                
                if hitRect.contains(locationInTextContainer) {
                    onToggleCheckbox?(charIndex)
                    return
                }
            }
        }
        
        super.mouseDown(with: event)
    }
}

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

        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        let coordinator = context.coordinator
        textView.onToggleCheckbox = { [weak coordinator] charIndex in
            coordinator?.toggleCheckbox(at: charIndex)
        }
        textView.delegate = coordinator
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

    final class Coordinator: NSObject, NSTextViewDelegate {
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

        func toggleCheckbox(at charIndex: Int) {
            guard let textView, let textStorage = textView.textStorage else { return }
            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            let line = text.substring(with: lineRange)
            
            let pattern = try! NSRegularExpression(pattern: "^([\\t ]*)(?:([-+*])[\\t ]+)?(\\[)([ xX]?)\\](?:[\\t ]+|$)")
            if let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let checkedRangeInLine = match.range(at: 4)
                let isChecked = checkedRangeInLine.location != NSNotFound && (line as NSString).substring(with: checkedRangeInLine).lowercased() == "x"
                
                let start = match.range(at: 3).location
                let length = (checkedRangeInLine.location != NSNotFound ? NSMaxRange(checkedRangeInLine) : NSMaxRange(match.range(at: 3))) + 1 - start
                let rangeToReplace = NSRange(location: lineRange.location + start, length: length)
                
                let replacement = isChecked ? "[ ]" : "[x]"
                
                if textView.shouldChangeText(in: rangeToReplace, replacementString: replacement) {
                    textStorage.replaceCharacters(in: rangeToReplace, with: replacement)
                    textView.didChangeText()
                }
            }
        }

        func refreshAppearance() {
            guard let textView,
                  let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager
            else { return }
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
            layoutManager.invalidateDisplay(
                forCharacterRange: NSRange(location: 0, length: textStorage.length)
            )
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.textColor
            ]
            isUpdatingAppearance = false
        }
    }
}
