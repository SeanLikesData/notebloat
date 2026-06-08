import AppKit

/// Applies non-destructive Markdown styling through NSLayoutManager temporary
/// attributes. The text storage always remains the original plain Markdown.
enum MarkdownStyler {
    private static let hiddenFont = NSFont.systemFont(ofSize: 0.1)

    private static let headingPattern = try! NSRegularExpression(
        pattern: "^(#{1,6})[\\t ]+(.+)$"
    )
    private static let boldPatterns = [
        try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*"),
        try! NSRegularExpression(pattern: "__(.+?)__")
    ]
    private static let italicPatterns = [
        try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)"),
        try! NSRegularExpression(pattern: "(?<!_)_([^_\\n]+)_(?!_)")
    ]
    private static let strikethroughPattern = try! NSRegularExpression(
        pattern: "~~(.+?)~~"
    )
    private static let codePattern = try! NSRegularExpression(
        pattern: "`([^`\\n]+)`"
    )
    private static let linkPattern = try! NSRegularExpression(
        pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)"
    )
    private static let quotePattern = try! NSRegularExpression(
        pattern: "^[\\t ]*>[\\t ]?"
    )
    private static let listPattern = try! NSRegularExpression(
        pattern: "^[\\t ]*(?:[-+*]|\\d+\\.)[\\t ]+"
    )

    static func apply(
        to layoutManager: NSLayoutManager,
        text: NSString,
        baseFont: NSFont,
        activeLineRanges: [NSRange],
        enabled: Bool
    ) {
        let fullRange = NSRange(location: 0, length: text.length)
        clearTemporaryAttributes(from: layoutManager, range: fullRange)
        guard text.length > 0 else { return }

        layoutManager.addTemporaryAttributes(
            [.font: baseFont, .foregroundColor: NSColor.textColor],
            forCharacterRange: fullRange
        )
        guard enabled else { return }

        var index = 0
        while index < text.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: index, length: 0)
            )

            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            if !activeLineRanges.contains(where: { rangesTouch($0, lineRange) }) {
                styleLine(
                    in: layoutManager,
                    text: text,
                    range: lineRange,
                    baseFont: baseFont
                )
            }

            guard lineEnd > index else { break }
            index = lineEnd
        }
    }

    private static func clearTemporaryAttributes(
        from layoutManager: NSLayoutManager,
        range: NSRange
    ) {
        let keys: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .strikethroughStyle,
            .underlineStyle
        ]
        for key in keys {
            layoutManager.removeTemporaryAttribute(key, forCharacterRange: range)
        }
    }

    private static func styleLine(
        in layoutManager: NSLayoutManager,
        text: NSString,
        range: NSRange,
        baseFont: NSFont
    ) {
        let line = text.substring(with: range) as NSString
        let localRange = NSRange(location: 0, length: line.length)

        if let match = headingPattern.firstMatch(in: line as String, range: localRange) {
            let level = match.range(at: 1).length
            let contentRange = absolute(match.range(at: 2), within: range)
            let sizeIncrease: CGFloat = [6, 4, 2, 1, 0, 0][level - 1]
            let headingFont = NSFont.systemFont(
                ofSize: baseFont.pointSize + sizeIncrease,
                weight: .bold
            )
            layoutManager.addTemporaryAttribute(
                .font,
                value: headingFont,
                forCharacterRange: contentRange
            )
            hide(
                NSRange(location: range.location, length: contentRange.location - range.location),
                in: layoutManager
            )
        }

        styleDelimitedMatches(
            boldPatterns,
            in: line,
            lineRange: range,
            layoutManager: layoutManager,
            contentAttributes: [
                .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            ]
        )
        styleDelimitedMatches(
            italicPatterns,
            in: line,
            lineRange: range,
            layoutManager: layoutManager,
            contentAttributes: [
                .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            ]
        )
        styleDelimitedMatches(
            [strikethroughPattern],
            in: line,
            lineRange: range,
            layoutManager: layoutManager,
            contentAttributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        )
        styleDelimitedMatches(
            [codePattern],
            in: line,
            lineRange: range,
            layoutManager: layoutManager,
            contentAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
                .backgroundColor: NSColor.quaternaryLabelColor
            ]
        )

        for match in linkPattern.matches(in: line as String, range: localRange) {
            let labelRange = absolute(match.range(at: 1), within: range)
            layoutManager.addTemporaryAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                forCharacterRange: labelRange
            )
            hide(NSRange(location: range.location + match.range.location, length: 1), in: layoutManager)
            let trailingStart = labelRange.location + labelRange.length
            let matchEnd = range.location + match.range.location + match.range.length
            hide(NSRange(location: trailingStart, length: matchEnd - trailingStart), in: layoutManager)
        }

        if let match = quotePattern.firstMatch(in: line as String, range: localRange) {
            let markerRange = absolute(match.range, within: range)
            hide(markerRange, in: layoutManager)
            let contentRange = NSRange(
                location: markerRange.location + markerRange.length,
                length: max(0, NSMaxRange(range) - NSMaxRange(markerRange))
            )
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                forCharacterRange: contentRange
            )
        } else if let match = listPattern.firstMatch(in: line as String, range: localRange) {
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                forCharacterRange: absolute(match.range, within: range)
            )
        }
    }

    private static func styleDelimitedMatches(
        _ patterns: [NSRegularExpression],
        in line: NSString,
        lineRange: NSRange,
        layoutManager: NSLayoutManager,
        contentAttributes: [NSAttributedString.Key: Any]
    ) {
        let localRange = NSRange(location: 0, length: line.length)
        for pattern in patterns {
            for match in pattern.matches(in: line as String, range: localRange) {
                let wholeRange = absolute(match.range, within: lineRange)
                let contentRange = absolute(match.range(at: 1), within: lineRange)
                layoutManager.addTemporaryAttributes(
                    contentAttributes,
                    forCharacterRange: contentRange
                )
                hide(
                    NSRange(location: wholeRange.location, length: contentRange.location - wholeRange.location),
                    in: layoutManager
                )
                hide(
                    NSRange(
                        location: NSMaxRange(contentRange),
                        length: NSMaxRange(wholeRange) - NSMaxRange(contentRange)
                    ),
                    in: layoutManager
                )
            }
        }
    }

    private static func hide(_ range: NSRange, in layoutManager: NSLayoutManager) {
        guard range.length > 0 else { return }
        layoutManager.addTemporaryAttributes(
            [.font: hiddenFont, .foregroundColor: NSColor.clear],
            forCharacterRange: range
        )
    }

    private static func absolute(_ localRange: NSRange, within lineRange: NSRange) -> NSRange {
        NSRange(location: lineRange.location + localRange.location, length: localRange.length)
    }

    private static func rangesTouch(_ left: NSRange, _ right: NSRange) -> Bool {
        if left.length == 0 {
            return left.location >= right.location && left.location <= NSMaxRange(right)
        }
        return NSIntersectionRange(left, right).length > 0
    }
}
