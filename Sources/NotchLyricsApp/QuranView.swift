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

    private func run(_ word: WordToken, first: Bool) -> Text {
        let progress = word.progress(at: time)
        let size = base * WordEmphasis.scale(progress: progress, style: .scale)
        let opacity = WordEmphasis.opacity(progress: progress, style: .scale)

        // Use the glyph only when its page font is actually loaded; otherwise
        // fall back to Unicode text in the system Arabic face.
        let pageFont = word.fontPage.flatMap { fontName($0) }
        let resolved = pageFont.flatMap { NSFont(name: $0, size: size) }
        let font = resolved ?? NSFont.systemFont(ofSize: size)
        let text = (resolved != nil ? word.glyph : nil) ?? (first ? word.text : " " + word.text)

        return Text(verbatim: text).font(Font(font)).foregroundColor(.white.opacity(opacity))
    }

    var body: some View {
        ZStack {
            NotchShape().fill(.black)
            if let line, !line.words.isEmpty {
                line.words.enumerated()
                    .reduce(Text(verbatim: "")) { $0 + run($1.element, first: $1.offset == 0) }
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .id(line.start)
            }
        }
        .animation(.easeOut(duration: 0.25), value: line?.start)
    }
}
