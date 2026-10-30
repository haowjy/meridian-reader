import SwiftUI

/// Every setting in the app, on the Library's list style (cards on paper, `SectionHeader`s), top to
/// bottom:
///
/// ```
/// Settings                                         ⋯ / Done
/// Listening    Voice ›, Language ›, Speed ›
/// Appearance / Reading   Appearance ›, Reading › (one card; drill-ins)
/// Browsing     Block Ads (on)
/// Prepared Audio & Storage   Prepared audio ›, sizes, Version (long-press: developer options)
/// About        Privacy Policy, Support, Acknowledgements
/// Developer    (developer options only) listen debug, fake extraction failure, the panel
/// ```
///
/// Compact width shows it in place, the chrome's Settings destination (`placement` `.destination`):
/// the title heads the list as the Library home's does, the chrome's Search Settings filters the
/// rows (`SettingsSearch`), and the list scrolls under the chrome. Regular width shows it as a sheet
/// with Done (`.sheet`), unfiltered.
///
/// Reading opens the same `ReadingAppearancePanel` as Aa on the Reader and Now Playing, so the two
/// never disagree.
struct SettingsView: View {
    enum Placement {
        /// Regular width's Settings sheet.
        case sheet(onDone: () -> Void)
        /// The compact chrome's Settings destination.
        case destination
    }

    @Bindable var speech: SpeechController
    let placement: Placement

    @Environment(\.readingAppearance) private var reading
    @Environment(ContentBlocker.self) private var contentBlocker
    @Environment(DeveloperSettings.self) private var developer
    @Environment(ShellState.self) private var shell
    /// Confirmation after the version row's long-press toggles developer options.
    @State private var developerToggleNotice: String?
    /// The sheet's pushed pages (in place, they are the shell's: `ShellState.settingsPath`).
    @State private var sheetPath: [SettingsRoute] = []

    private var inPlace: Bool {
        if case .destination = placement { true } else { false }
    }

    private var search: SettingsSearch {
        inPlace && shell.settingsSearch.isActive ? SettingsSearch(text: shell.settingsSearch.text) : SettingsSearch()
    }

    /// Every section the list can show, for Search Settings' "no results".
    private var groups: [SettingsSearch.Group] {
        [ListeningSettingsSection.group, Self.appearanceGroup, BrowsingSettingsSection.group,
         StorageSettingsSection<EmptyView>.group, AboutSettingsSection.group]
            + (developer.isEnabled ? [DeveloperSettingsSection.group] : [])
    }

    private var path: Binding<[SettingsRoute]> {
        inPlace ? Binding(get: { shell.settingsPath }, set: { shell.settingsPath = $0 }) : $sheetPath
    }

    var body: some View {
        NavigationStack(path: path) {
            Group {
                if inPlace { list.statusBarBacking() } else { list }
            }
                .navigationTitle(Verbs.settings)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if case .sheet(let onDone) = placement {
                        SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "settingsDone", action: onDone)
                    }
                }
                .toolbar(inPlace ? .hidden : .automatic, for: .navigationBar)
                .modifier(CompactChromeScroll(isCompact: inPlace))
                // In place a pushed page reports its own scroll: a modifier above the stack doesn't reach it.
                .navigationDestination(for: SettingsRoute.self) { page($0).modifier(CompactChromeScroll(isCompact: inPlace)) }
        }
        .modifier(CompactChromeInsets(isCompact: inPlace))
        .scrollDismissesKeyboard(.interactively)
        .environment(\.settingsSearch, search)
        .alert(developerToggleNotice ?? "", isPresented: Binding(
            get: { developerToggleNotice != nil },
            set: { if !$0 { developerToggleNotice = nil } }
        )) {
            Button(Verbs.ok, role: .cancel) {}
        } message: {
            Text(developer.isEnabled
                 ? "Debug tools are shown in Settings › Developer. Long-press the version again to hide them."
                 : "Debug tools are hidden.")
        }
    }

    private var list: some View {
        List {
            if inPlace {
                Section {
                    EmptyView()
                } header: {
                    TitleLine(title: Verbs.settings) {
                        TitleMenuButton(id: "settingsMore", blocks: titleMenu)
                    }
                    .accessibilityIdentifier("settingsTitle")
                    .listHeader()
                }
            }
            ListeningSettingsSection(speech: speech)
            appearanceAndReadingSection
            BrowsingSettingsSection(blocker: contentBlocker)
            StorageSettingsSection(speech: speech, versionRow: { versionRow })
            AboutSettingsSection()
            if developer.isEnabled {
                DeveloperSettingsSection()
            }
            if search.isFiltering && !groups.contains(where: search.shows) {
                Section {
                    ContentUnavailableView.search(text: search.text)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .cardListStyle()
        // Tighter than Library cards: Settings root has many short sections.
        .listSectionSpacing(Spacing.xs)
        .accessibilityIdentifier("settingsList")
    }

    @ViewBuilder
    private func page(_ route: SettingsRoute) -> some View {
        switch route {
        case .voice: VoicePage(speech: speech)
        case .language: LanguagePage(speech: speech)
        case .speed: SpeedPage(speech: speech)
        case .appearance: AppearanceSettingsPage(appearance: AppAppearance.shared)
        case .reading: ReadingSettingsPage()
        case .preparedAudio: PreparedAudioList()
        case .acknowledgements: AcknowledgementsView()
        }
    }

    /// The title line's ⋯ in place: Settings has no rows of its own (its list holds Prepared Audio),
    /// so the app-wide ones that remain on compact width: Saved, History, Listen.
    private var titleMenu: [[MenuRow]] {
        let listen = MenuRow(id: "moreListen", title: Verbs.listen, icon: Icons.listen,
                             availability: MenuAvailability(when: speech.nowPlaying != nil),
                             accessibilityHint: String(localized: "Go to Now Playing"), action: shell.showNowPlaying)
        return MenuContext(screen: [], tiles: MenuContext.tiles(shell, compact: true, last: listen)).blocks
    }

    // MARK: - Appearance / Reading drill-ins (one card)

    private static let appearanceGroup = SettingsSearch.Group(title: "", rows: [String(localized: "Appearance"),
                                                                                 String(localized: "Reading")])

    @ViewBuilder
    private var appearanceAndReadingSection: some View {
        let group = Self.appearanceGroup
        if search.shows(group) {
            Section {
                if search.shows(group.rows[0], in: group) {
                    SettingsLinkRow(title: group.rows[0], symbol: nil, value: AppAppearance.shared.mode.title,
                                    accessibilityID: "settingsAppearance", route: .appearance)
                }
                if search.shows(group.rows[1], in: group) {
                    SettingsLinkRow(title: group.rows[1], symbol: nil, value: reading.theme.title,
                                    accessibilityID: "settingsReading", route: .reading)
                }
            }
            .listCard()
        }
    }

    // MARK: - Version / developer options (last row of Storage card)

    private var versionRow: some View {
        SymbolRow(DeveloperSettings.versionLabel, symbol: nil, ink: Palette.secondaryInk) {
            if developer.isEnabled {
                Text("Developer options")
                    .typeStyle(.caption)
            }
        }
        .onLongPressGesture(minimumDuration: DeveloperSettings.unlockPressSeconds) {
            toggleDeveloperOptions()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsVersionRow")
        .accessibilityAction(named: developer.isEnabled
                             ? "Turn off developer options" : "Turn on developer options") {
            toggleDeveloperOptions()
        }
    }

    private func toggleDeveloperOptions() {
        developer.isEnabled.toggle()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        developerToggleNotice = developer.isEnabled ? "Developer options on" : "Developer options off"
    }
}


/// Settings › About: Privacy Policy and Support on GitHub Pages (App Store Guideline 5.1.1),
/// plus Acknowledgements for the on-device TTS / extraction stack.
private struct AboutSettingsSection: View {
    private static let privacyURL = URL(string: "https://haowjy.github.io/meridian-reader/privacy.html")!
    private static let supportURL = URL(string: "https://haowjy.github.io/meridian-reader/support.html")!
    private static let privacy = String(localized: "Privacy Policy")
    private static let support = String(localized: "Support")
    private static let acknowledgements = String(localized: "Acknowledgements")
    static let group = SettingsSearch.Group(title: String(localized: "About"), rows: [privacy, support, acknowledgements])

    @Environment(\.settingsSearch) private var search

    var body: some View {
        if search.shows(Self.group) {
            Section {
                if search.shows(Self.privacy, in: Self.group) {
                    link(Self.privacy, symbol: Icons.privacy, to: Self.privacyURL, id: "settingsPrivacyPolicy")
                }
                if search.shows(Self.support, in: Self.group) {
                    link(Self.support, symbol: Icons.support, to: Self.supportURL, id: "settingsSupport")
                }
                if search.shows(Self.acknowledgements, in: Self.group) {
                    SettingsLinkRow(title: Self.acknowledgements, symbol: Icons.acknowledgements,
                                    value: "", accessibilityID: "settingsAcknowledgements", route: .acknowledgements)
                }
            } header: {
                SectionHeader(title: Self.group.title, size: .settings).listHeader()
            }
            .listCard()
        }
    }

    private func link(_ title: String, symbol: String, to url: URL, id: String) -> some View {
        Link(destination: url) {
            SymbolRow(title, symbol: symbol) {
                Image(systemName: Icons.disclosure)
                    .foregroundStyle(Palette.secondaryInk)
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.plain)
        .tint(Palette.ink)
        .accessibilityIdentifier(id)
    }
}

/// Settings › Appearance: the app's appearance and its colour (`AppAppearance`).
private struct AppearanceSettingsPage: View {
    @Bindable var appearance: AppAppearance

    var body: some View {
        List {
            Section {
                SettingsControlRow(title: Verbs.theme) {
                    ChoicePicker(options: AppearanceMode.allCases, selection: $appearance.mode,
                                 identifier: "appearanceMode") { mode in
                        Text(mode.title).typeStyle(.row)
                    }
                }
                SettingsControlRow(title: String(localized: "Color")) {
                    AccentThemePicker(selection: $appearance.accent)
                }
            }
            .listCard()
        }
        .cardListStyle()
        .navigationTitle(String(localized: "Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Reading: the shared Aa panel (`ReadingAppearancePanel` → `TextAppearancePanel`).
private struct ReadingSettingsPage: View {
    @Environment(\.readingAppearance) private var appearance

    var body: some View {
        List {
            Section {
                ReadingAppearancePanel(appearance: appearance)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("How the Reader and Now Playing show articles. Aa at the top of either changes the same settings.")
                    .listFooter()
            }
            .listCard()
        }
        .cardListStyle()
        .navigationTitle(String(localized: "Reading"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settingsReadingPage")
    }
}

/// Settings › Browsing: Block Ads (`ContentBlocker`) and Search Suggestions (`SearchSuggestions`).
private struct BrowsingSettingsSection: View {
    @Bindable var blocker: ContentBlocker
    @AppStorage(SearchSuggestions.storageKey) private var suggestions = true
    @Environment(\.settingsSearch) private var search

    private static let blockAds = String(localized: "Block Ads")
    private static let suggestionsTitle = String(localized: "Search Suggestions")
    static let group = SettingsSearch.Group(title: String(localized: "Browsing"), rows: [blockAds, suggestionsTitle])

    var body: some View {
        if search.shows(Self.group) {
            Section {
                if search.shows(Self.blockAds, in: Self.group) {
                    SettingsToggleRow(title: Self.blockAds, symbol: Icons.blockAds,
                                      isOn: $blocker.isEnabled, accessibilityID: "blockAdsToggle")
                }
                if search.shows(Self.suggestionsTitle, in: Self.group) {
                    SettingsToggleRow(title: Self.suggestionsTitle, symbol: Icons.search,
                                      isOn: $suggestions, accessibilityID: "searchSuggestionsToggle")
                }
            } header: {
                SectionHeader(title: Self.group.title, size: .settings).listHeader()
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Blocks ads and trackers on pages loaded after you change this.")
                    Text("Search Suggestions sends what you type in the address field to Google to suggest searches.")
                }
                .listFooter()
            }
            .listCard()
        }
    }
}

/// Settings › Prepared Audio & Storage (C134): the Prepared Audio list, and the audio kept on
/// this iPhone in two figures: prepared (chosen, never cleared automatically) and from listening
/// (cleared once its article leaves Recent).
private struct StorageSettingsSection<VersionRow: View>: View {
    let speech: SpeechController
    @ViewBuilder var versionRow: () -> VersionRow

    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(\.settingsSearch) private var search
    @State private var preparedBytes: Int64?
    @State private var listeningBytes: Int64?

    private static var preparedSize: String { String(localized: "Prepared Audio") }
    private static var listeningSize: String { String(localized: "Audio From Listening") }
    static var group: SettingsSearch.Group {
        SettingsSearch.Group(title: String(localized: "Prepared Audio & Storage"),
                             rows: [Verbs.preparedAudio, preparedSize, listeningSize, DeveloperSettings.versionLabel])
    }

    var body: some View {
        if search.shows(Self.group) {
            section
        }
    }

    private var section: some View {
        let overview = preparedAudio.overview
        let group = Self.group
        return Section {
            if search.shows(Verbs.preparedAudio, in: group) {
                SettingsLinkRow(title: Verbs.preparedAudio, symbol: Icons.preparedAudio,
                                value: overview.isEmpty ? String(localized: "None") : "\(overview.done.count + overview.queued.count + overview.differentVoice.count)",
                                accessibilityID: "settingsPreparedAudio", route: .preparedAudio)
            }
            if search.shows(Self.preparedSize, in: group) {
                sizeRow(Self.preparedSize, bytes: preparedBytes, id: "settingsPreparedSize")
            }
            if search.shows(Self.listeningSize, in: group) {
                sizeRow(Self.listeningSize, bytes: listeningBytes, id: "settingsAudioSize")
            }
            if search.shows(DeveloperSettings.versionLabel, in: group) {
                versionRow()
            }
        } header: {
            SectionHeader(title: group.title, size: .settings).listHeader()
        } footer: {
            Text("Prepared stays until you delete it. Listening audio clears when it leaves History.")
                .listFooter()
        }
        .listCard()
        .task {
            let cache = speech.localTTS.audioCache
            let held = Set(preparedAudio.heldArticleKeys)
            let dirs = cache.cachedArticleKeys().map { (held.contains($0), cache.directory(for: $0)) }
            let (p, l) = await Task.detached(priority: .utility) {
                dirs.reduce((Int64(0), Int64(0))) { sum, d in
                    let bytes = FileSizes.allocatedBytes(at: d.1)
                    return d.0 ? (sum.0 + bytes, sum.1) : (sum.0, sum.1 + bytes)
                }
            }.value
            preparedBytes = p
            listeningBytes = l
        }
    }

    private func sizeRow(_ title: String, bytes: Int64?, id: String) -> some View {
        SymbolRow(title, symbol: Icons.storage) {
            Text(bytes.map(FileSizes.label) ?? "…")
                .typeStyle(.row)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// Settings › Developer (developer options only, at the bottom): the listen debug chip on Now
/// Playing, a fake failure for every extraction, and the listen debug panel.
private struct DeveloperSettingsSection: View {
    @Environment(DeveloperSettings.self) private var developer
    @Environment(ShellState.self) private var shell

    @Environment(\.settingsSearch) private var search

    private static let fakeFailure = String(localized: "Fake Extraction Failure")
    private static let panel = String(localized: "Listen Debug Panel")
    static let group = SettingsSearch.Group(title: String(localized: "Developer"),
                                            rows: [Verbs.listenDebug, fakeFailure, panel])

    var body: some View {
        if search.shows(Self.group) {
            section
        }
    }

    private var section: some View {
        @Bindable var developer = developer
        return Section {
            if search.shows(Verbs.listenDebug, in: Self.group) {
                SettingsToggleRow(title: Verbs.listenDebug, symbol: Icons.debug,
                                  isOn: $developer.listenDebugEnabled, accessibilityID: "listenDebugEnabledToggle")
            }
            if search.shows(Self.fakeFailure, in: Self.group) {
                SettingsToggleRow(title: Self.fakeFailure, symbol: Icons.warning,
                                  isOn: $developer.fakeExtractionFailure, accessibilityID: "fakeExtractionFailureToggle")
            }
            if search.shows(Self.panel, in: Self.group) {
                Button {
                    // Over Settings, which stay when it closes (`ShellState.overSheet`); Settings in
                    // place has no sheet under it.
                    shell.present(.listenDebug)
                } label: {
                    SymbolRow(Self.panel, symbol: Icons.debug) {
                        Image(systemName: Icons.disclosure)
                            .disclosureSymbol()
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listenDebugSettings")
            }
        } header: {
            SectionHeader(title: Self.group.title, size: .settings).listHeader()
        } footer: {
            Text("Listen Debug shows a Debug chip on Now Playing for a live render queue overlay; a long-press on ▶ there opens the panel. Fake Extraction Failure makes every extraction fail (Reader, Save, Follow, Prepared Audio) until the app quits.")
                .listFooter()
        }
        .listCard()
    }
}
