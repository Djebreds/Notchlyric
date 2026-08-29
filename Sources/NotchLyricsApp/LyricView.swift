import SwiftUI
import NotchLyricsCore

/// Square top corners, rounded bottom — so the panel reads as an extension of
/// the notch rather than a separate floating box.
struct NotchShape: Shape {
    var radius: CGFloat = 14
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct LyricView: View {
    let line: LyricLine?
    let time: TimeInterval
    let position: Position

    private var isEar: Bool { position == .earLeft || position == .earRight }

    private var font: Font {
        isEar ? .system(size: 12, weight: .medium)
              : .system(size: position == .notch ? 15 : 14, weight: .semibold)
    }

    var body: some View {
        ZStack {
            background
            if let line, !line.isBlank {
                sweptText(line)
                    .font(font)
                    .lineLimit(isEar ? 1 : 2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, isEar ? 8 : 16)
                    .padding(.bottom, position == .notch ? 10 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: position == .notch ? .bottom : .center)
                    .id(line.start)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: line?.start)
    }

    @ViewBuilder private var background: some View {
        switch position {
        case .notch:
            NotchShape().fill(.black)
        case .earLeft, .earRight:
            Color.clear
        case .bottomRight:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
    }

    /// Per-word brightness rather than one gradient across the whole block.
    ///
    /// A single horizontal mask breaks on wrapped lines: words on the second
    /// visual row sit left of the sweep edge and light up early. Colouring each
    /// word by its own progress is wrap-correct and still reads as a
    /// left-to-right karaoke sweep.
    private func sweptText(_ line: LyricLine) -> Text {
        line.words.enumerated().reduce(Text(verbatim: "")) { acc, pair in
            let (i, w) = pair
            let progress = w.progress(at: time)
            let piece = Text(verbatim: i == 0 ? w.text : " " + w.text)
                .foregroundColor(.white.opacity(0.30 + 0.70 * progress))
            return acc + piece
        }
    }
}
