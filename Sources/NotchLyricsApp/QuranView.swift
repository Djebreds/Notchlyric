import SwiftUI
import NotchLyricsCore

/// Renders one mushaf line right-to-left, one Text run per word so each can be
/// coloured and sized independently. Fonts resolve per word because a line can
/// straddle a page boundary.
struct QuranView: View {
    let line: LyricLine?
    let time: TimeInterval
    let fontName: (Int) -> String?

    private let base: CGFloat = 23

    /// Base font for a word: its mushaf page face when loaded, otherwise the
    /// system Arabic face. Always at base size — emphasis is applied visually.
    private func baseFont(_ word: WordToken) -> Font {
        if let name = word.fontPage.flatMap(fontName),
           let f = NSFont(name: name, size: base) {
            return Font(f)
        }
        return .system(size: base)
    }

    /// Use the QCF glyph only when its page font actually loaded; otherwise
    /// fall back to Unicode text, which the system face can render.
    private func shown(_ word: WordToken) -> String {
        let loaded = word.fontPage.flatMap(fontName).flatMap { NSFont(name: $0, size: base) } != nil
        return (loaded ? word.glyph : nil) ?? word.text
    }

    var body: some View {
        ZStack {
            NotchShape().fill(.black)
            if let line, !line.words.isEmpty {
                WordFlow(words: line.words, time: time, style: .scale, rtl: true,
                         spacing: 6, font: baseFont, text: shown)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .id(line.start)
            }
        }
        .animation(.easeOut(duration: 0.25), value: line?.start)
    }
}
