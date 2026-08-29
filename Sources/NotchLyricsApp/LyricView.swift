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
    var style: SweepStyle = .scale
    var romanize: Bool = true

    private var isEar: Bool { position == .earLeft || position == .earRight }

    private var baseSize: CGFloat {
        isEar ? 12 : (position == .notch ? 15 : 14)
    }

    private var weight: Font.Weight { isEar ? .medium : .semibold }

    private var font: Font { .system(size: baseSize, weight: weight) }

    var body: some View {
        ZStack {
            background
            if let line, !line.isBlank {
                WordFlow(words: line.words, time: time, style: style, rtl: false,
                         spacing: isEar ? 5 : 7, lineID: line.start,
                         font: { _ in .system(size: baseSize, weight: weight) },
                         text: { romanize ? $0.text : ($0.original ?? $0.text) })
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
}
