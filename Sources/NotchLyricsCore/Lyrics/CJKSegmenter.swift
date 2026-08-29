import Foundation

/// Splits CJK text into words and romanizes them.
///
/// Chinese, Japanese and Korean are written without spaces, so splitting on
/// whitespace yields roughly one "word" per line — measured at 1.3 against 6.1
/// for English. Per-word tracking is therefore absent, not merely coarse, until
/// the text is tokenized properly.
public enum CJKSegmenter {
    public struct Segment: Equatable, Sendable {
        public let text: String     // the source token
        public let romaji: String   // Latin transcription, or the token itself
        public init(text: String, romaji: String) {
            self.text = text; self.romaji = romaji
        }
    }

    /// A line is treated as CJK once this share of its non-space characters are
    /// Han, Kana or Hangul. The threshold keeps a stray character in an English
    /// line from triggering reprocessing.
    private static let threshold = 0.2

    public static func isCJK(_ text: String) -> Bool {
        let meaningful = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !meaningful.isEmpty else { return false }
        let cjk = meaningful.filter(isCJKScalar).count
        return Double(cjk) / Double(meaningful.count) >= threshold
    }

    private static func isCJKScalar(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x30FF,      // hiragana, katakana
             0x3400...0x4DBF,      // CJK ext A
             0x4E00...0x9FFF,      // CJK unified
             0xF900...0xFAFF,      // compatibility ideographs
             0xAC00...0xD7AF,      // hangul syllables
             0x1100...0x11FF:      // hangul jamo
            return true
        default:
            return false
        }
    }

    /// Tokenizes and romanizes. Returns an empty array for empty input.
    ///
    /// Uses CFStringTokenizer's Latin transcription rather than
    /// CFStringTransform, which returns *Chinese* readings for kanji and would
    /// render 東京都 as "dong jing dou" instead of "toukyouto".
    public static func segment(_ text: String) -> [Segment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let cf = trimmed as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, cf, CFRangeMake(0, CFStringGetLength(cf)),
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja") as CFLocale)

        var out: [Segment] = []
        let ns = trimmed as NSString
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard r.length > 0 else { continue }
            let token = ns.substring(with: NSRange(location: r.location, length: r.length))
            guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            // Latin tokens carry no transcription; keep them as they are.
            let romaji = (latin?.isEmpty == false ? latin! : token)
            out.append(Segment(text: token, romaji: romaji))
        }

        // If the tokenizer produced nothing usable, fall back to a space split.
        guard !out.isEmpty else {
            return trimmed.split(separator: " ").map { Segment(text: String($0), romaji: String($0)) }
        }
        return out
    }
}
