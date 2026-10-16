import SwiftUI
import XCTest
@testable import MeridianReader

/// The appearance stores: what a new install starts with, what a change stores, what the next
/// launch reads back, and that the reading store's two editors (Settings › Reading and the Aa
/// panel) share one value.
final class AppearanceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "AppearanceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testANewInstallReadsAsBefore() {
        let reading = ReadingAppearance(defaults: defaults)
        XCTAssertEqual(reading.theme, .matchApp)
        XCTAssertEqual(reading.font, .serif)
        XCTAssertEqual(reading.textSizeStep, ReadingTextSize.defaultStep)
        XCTAssertEqual(reading.textScale, 1)
        XCTAssertEqual(reading.lineSpacing, .normal)
        let app = AppAppearance(defaults: defaults)
        XCTAssertEqual(app.mode, .system)
        XCTAssertEqual(app.accent, .jade)
    }

    func testReadingChoicesPersistAcrossLaunches() {
        let reading = ReadingAppearance(defaults: defaults)
        reading.theme = .sepia
        reading.font = .rounded
        reading.growText()
        reading.growText()
        reading.lineSpacing = .relaxed

        let next = ReadingAppearance(defaults: defaults)
        XCTAssertEqual(next.theme, .sepia)
        XCTAssertEqual(next.font, .rounded)
        XCTAssertEqual(next.textSizeStep, ReadingTextSize.defaultStep + 2)
        XCTAssertEqual(next.lineSpacing, .relaxed)
        XCTAssertEqual(defaults.string(forKey: ReadingAppearance.themeKey), "sepia", "the stored key and value")
    }

    func testAppChoicesPersistAcrossLaunches() {
        let app = AppAppearance(defaults: defaults)
        app.mode = .dark
        app.accent = .plum
        let next = AppAppearance(defaults: defaults)
        XCTAssertEqual(next.mode, .dark)
        XCTAssertEqual(next.accent, .plum)
        XCTAssertEqual(defaults.string(forKey: AppAppearance.accentKey), "plum")
    }

    func testTextSizeStaysWithinItsSteps() {
        let reading = ReadingAppearance(defaults: defaults)
        for _ in 0..<20 { reading.shrinkText() }
        XCTAssertEqual(reading.textSizeStep, ReadingTextSize.steps.lowerBound)
        XCTAssertFalse(reading.canShrinkText)
        for _ in 0..<20 { reading.growText() }
        XCTAssertEqual(reading.textSizeStep, ReadingTextSize.steps.upperBound)
        XCTAssertFalse(reading.canGrowText)
        reading.textSizeStep = 99
        XCTAssertEqual(reading.textSizeStep, ReadingTextSize.steps.upperBound, "an assignment past the end is clamped")
        defaults.set(-5, forKey: ReadingAppearance.textSizeKey)
        XCTAssertEqual(ReadingAppearance(defaults: defaults).textSizeStep, ReadingTextSize.steps.lowerBound,
                       "a stored value past the end is clamped")
        XCTAssertEqual(ReadingTextSize.label(step: ReadingTextSize.defaultStep), "100%")
    }

    func testUnknownStoredValuesFallBackToTheDefaults() {
        defaults.set("neon", forKey: ReadingAppearance.themeKey)
        defaults.set("comic", forKey: ReadingAppearance.fontKey)
        defaults.set("teal", forKey: AppAppearance.accentKey)
        XCTAssertEqual(ReadingAppearance(defaults: defaults).theme, .matchApp)
        XCTAssertEqual(ReadingAppearance(defaults: defaults).font, .serif)
        XCTAssertEqual(AppAppearance(defaults: defaults).accent, .jade)
    }

    /// Settings › Reading and the Aa panel bind to the same store: a change through one binding
    /// is what the other reads, and the palette both sheets draw follows it.
    func testBothEditorsShareOneValue() {
        let reading = ReadingAppearance(defaults: defaults)
        let settings = Bindable(reading)
        let panel = Bindable(reading)
        settings.theme.wrappedValue = .black
        XCTAssertEqual(panel.theme.wrappedValue, .black)
        panel.font.wrappedValue = .sans
        XCTAssertEqual(settings.font.wrappedValue, .sans)
        XCTAssertEqual(reading.palette(accent: .jade).theme, .black)
        XCTAssertTrue(reading.palette(accent: .jade).isDark)
    }

    func testResetGoesBackToTheDefaults() {
        let reading = ReadingAppearance(defaults: defaults)
        reading.theme = .dark
        reading.font = .sans
        reading.growText()
        reading.lineSpacing = .compact
        reading.reset()
        XCTAssertEqual(reading.theme, .matchApp)
        XCTAssertEqual(reading.font, .serif)
        XCTAssertEqual(reading.textSizeStep, ReadingTextSize.defaultStep)
        XCTAssertEqual(reading.lineSpacing, .normal)
    }

    /// The page's CSS variables carry the look: a theme's colours, the typeface and spacing.
    func testTheLookWritesItsVariables() {
        let look = ReadingStyle.Look(colors: .init(ReadingTheme.sepia.palette(accent: .jade), scheme: .dark),
                                     font: .sans, lineSpacing: .compact, textScale: 1.2)
        let vars = look.cssVariables
        XCTAssertTrue(vars.contains("--paper: #F4ECD8"), vars)
        XCTAssertTrue(vars.contains("color-scheme: light"), "Sepia is light whatever the app: \(vars)")
        XCTAssertTrue(vars.contains("--leading: 1.4"), vars)
        XCTAssertTrue(vars.contains("--scale: 1.20"), vars)
        XCTAssertTrue(vars.contains("-apple-system"), vars)
        let match = ReadingStyle.Colors(ReadingTheme.matchApp.palette(accent: .jade), scheme: .dark)
        XCTAssertEqual(match.paper, "#141416", "Match App follows the app's appearance")
        XCTAssertEqual(match.scheme, .dark)
    }
}
