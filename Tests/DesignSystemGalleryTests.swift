import SwiftUI
import XCTest
@testable import Reader

/// Every design-system gallery (the states its previews show) renders in light, dark and the
/// largest text size, and the accent asset matches the palette. Contrast: `ColorContrastTests`.
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
        ("Toast", AnyView(ToastGallery())),
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
                // AX5 galleries run long; at 2× the tallest outgrow what PNG encoding accepts.
                renderer.scale = variant == .largestText ? 1 : 2
                let image = try XCTUnwrap(renderer.uiImage, "\(name) \(variant.rawValue)")
                XCTAssertEqual(image.size.width, PreviewGallery<EmptyView>.width, accuracy: 1, "\(name) \(variant.rawValue)")
                XCTAssertGreaterThan(image.size.height, 40, "\(name) \(variant.rawValue)")
                if let dir, let png = image.pngData() {
                    try png.write(to: dir.appendingPathComponent("\(name)-\(variant.rawValue).png"))
                }
            }
        }
    }

    /// System controls tint with the asset catalog's AccentColor; it must be `Palette.accent`.
    func testAccentAssetMatchesThePalette() throws {
        let asset = try XCTUnwrap(UIColor(named: "AccentColor"))
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(Self.rgb(asset.resolvedColor(with: traits)),
                           Self.rgb(UIColor(Palette.accent).resolvedColor(with: traits)), "\(style.rawValue)")
        }
    }

    private static func rgb(_ color: UIColor) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return [r, g, b].map { Int(($0 * 255).rounded()) }
    }
}
