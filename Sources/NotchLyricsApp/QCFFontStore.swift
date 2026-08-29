import AppKit
import CoreText

/// Fetches and registers QCF mushaf page fonts.
///
/// quran.com uses 604 fonts, one per page, where each glyph is a whole word.
/// They are fetched on demand at ~41 KB each because most sessions touch only
/// a few pages; bundling all of them would cost ~24 MB.
@MainActor
final class QCFFontStore {
    private var registered: Set<Int> = []
    private var failed: Set<Int> = []
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("NotchLyrics/fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func psName(_ page: Int) -> String { String(format: "QCF2%03d", page) }

    /// PostScript name for a page, or nil if that page is not available yet.
    func fontName(forPage page: Int) -> String? {
        registered.contains(page) ? psName(page) : nil
    }

    func prefetch(pages: Set<Int>) async {
        for page in pages.sorted() where !registered.contains(page) && !failed.contains(page) {
            await load(page: page)
        }
    }

    private func load(page: Int) async {
        // A previous launch may already have registered this face.
        if NSFont(name: psName(page), size: 12) != nil { registered.insert(page); return }

        let file = directory.appendingPathComponent(String(format: "p%03d.woff2", page))
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let url = URL(string:
                "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p\(page).woff2")
            else { failed.insert(page); return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    failed.insert(page); return
                }
                try data.write(to: file, options: .atomic)
            } catch {
                failed.insert(page); return
            }
        }

        var err: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(file as CFURL, .process, &err) {
            registered.insert(page)
        } else if NSFont(name: psName(page), size: 12) != nil {
            registered.insert(page)
        } else {
            failed.insert(page)
        }
    }
}
