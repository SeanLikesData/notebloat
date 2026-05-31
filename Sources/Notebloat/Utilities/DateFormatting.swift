import Foundation

/// Produces the "165 chars • 25 words" counter shown in the bottom bar.
enum TextStats {
    static func summary(for text: String) -> String {
        let characterCount = text.count
        let wordCount = text.split { $0.isWhitespace }.count

        let characterLabel = characterCount == 1 ? "char" : "chars"
        let wordLabel = wordCount == 1 ? "word" : "words"
        return "\(characterCount) \(characterLabel) • \(wordCount) \(wordLabel)"
    }
}
