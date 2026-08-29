import SwiftUI

/// Shown in place of a lyric during instrumental breaks and track changes.
///
/// A neutral note rather than the last line, so the overlay neither blinks out
/// nor sits stuck on a sentence that finished some time ago.
struct IdleSymbolView: View {
    var body: some View {
        ZStack {
            NotchShape().fill(.black)
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
