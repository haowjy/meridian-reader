import SwiftUI
import XCTest
@testable import Reader

/// Every design-system gallery (the states its previews show) renders in light, dark and the
/// largest text size, and the palette's text pairs keep 4.5:1 in both appearances.
///
/// With `TEST_RUNNER_READER_GALLERY_DIR=<dir>` in xcodebuild's environment, each render is also
/// written to `<dir>/<Gallery>-<variant>.png` for review.
@MainActor
final class DesignSystemGalleryTests: XCTestCase {
    private static let galleries: [(String, AnyView)] = [
        ("Tokens", AnyView(TokensGallery())),
        ("PlayStateButton", AnyView(PlayStateButtonGallery())),
        ("PillButton", AnyView(PillButtonGallery())),
        ("AddressField", AnyView(AddressFieldGallery())),
        ("SearchField", AnyView(SearchFieldGallery())),
        ("SectionHeader", AnyView(SectionHeaderGallery())),
        ("ListRow", AnyView(ListRowGallery())),
        ("ContinueCard", AnyView(ContinueCardGallery())),
        ("FolderHeader", AnyView(FolderHeaderGallery())),
        ("ScrubBar", AnyView(ScrubBarGallery())),
        ("NowPlayingBar", AnyView(NowPlayingBarGallery())),
        ("Sheet", AnyView(SheetGallery())),
        ("ReaderSheet", AnyView(ReaderSheetGallery())),
        ("NowPlayingSheet", AnyView(NowPlayingSheetGallery())),
        ("BottomToolbar", AnyView(BottomToolbarGallery())),
        ("MorphMenu", AnyView(MorphMenuGallery())),
    ]

    func testEveryGalleryRendersInEveryVariant() throws {
        let dir = ProcessInfo.processInfo.environment["READER_GALLERY_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0) }
        if let dir { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

        for (name, gallery) in Self.galleries {
            for variant in PreviewVariant.allCases {
                let renderer = ImageRenderer(content: gallery.previewVariant(variant))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage, "\(name) \(variant.rawValue)")
                XCTAssertEqual(image.size.width, PreviewGallery<EmptyView>.width, accuracy: 1, "\(name) \(variant.rawValue)")
                XCTAssertGreaterThan(image.size.height, 40, "\(name) \(variant.rawValue)")
                if let dir, let png = image.pngData() {
                    try png.write(to: dir.appendingPathComponent("\(name)-\(variant.rawValue).png"))
                }
            }
        }
    }

    func testTextColoursKeepContrastInBothAppearances() {
        let backgrounds: [(String, Color)] = [
            ("paper", Palette.paper), ("chrome", Palette.chrome), ("playingTint", Palette.playingTint),
        ]
        let texts: [(String, Color)] = [
            ("ink", Palette.ink), ("secondaryInk", Palette.secondaryInk), ("accent", Palette.accent),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for (bgName, bg) in backgrounds {
                for (textName, text) in texts {
                    let ratio = Self.contrast(UIColor(text).resolvedColor(with: traits),
                                              UIColor(bg).resolvedColor(with: traits))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(textName) on \(bgName), \(style.rawValue)")
                }
            }
            let onAccent = Self.contrast(UIColor(Palette.onAccent).resolvedColor(with: traits),
                                         UIColor(Palette.accent).resolvedColor(with: traits))
            XCTAssertGreaterThanOrEqual(onAccent, 4.5, "onAccent on accent, \(style.rawValue)")
        }
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
