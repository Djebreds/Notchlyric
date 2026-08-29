import SwiftUI
import AppKit

/// Shown in place of a lyric during instrumental breaks and track changes.
struct ArtworkView: View {
    let image: NSImage

    var body: some View {
        ZStack {
            NotchShape().fill(.black)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.vertical, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
