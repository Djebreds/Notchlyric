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

    /// Fraction of the line already sung, derived from word spans.
    private var sweep: Double {
        guard let line, !line.words.isEmpty else { return 0 }
        let widths = line.words.map { Double($0.text.count + 1) }
        let total = widths.reduce(0, +)
        guard total > 0 else { return 0 }
        var done = 0.0
        for (i, w) in line.words.enumerated() {
            done += widths[i] * w.progress(at: time)
        }
        return min(1, max(0, done / total))
    }

    private var font: Font {
        isEar ? .system(size: 12, weight: .medium)
              : .system(size: position == .notch ? 15 : 14, weight: .semibold)
    }

    var body: some View {
        ZStack {
            background
            if let line, !line.isBlank {
                textStack(line)
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

    private func styled(_ text: String) -> some View {
        Text(text)
            .font(font)
            .lineLimit(isEar ? 1 : 2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
    }

    private func textStack(_ line: LyricLine) -> some View {
        styled(line.text)
            .foregroundStyle(.white.opacity(0.34))
            .overlay(alignment: .leading) {
                // Bright layer revealed left-to-right as the line is sung.
                styled(line.text)
                    .foregroundStyle(.white)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: max(0, sweep - 0.04)),
                                    .init(color: .clear, location: min(1, sweep + 0.04)),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
            }
    }
}
