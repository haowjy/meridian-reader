import SwiftUI

/// The browser's bottom chrome at regular width: the address field over the clustered dock, with
/// the browse tools in it. Compact width draws the browser's chrome in the shell's one host
/// (`ChromeHost`), whose address field is `BrowseAddressField`, the same one this uses.
///
/// A thin load-progress line sits on its top edge. It is its own view so `estimatedProgress`
/// ticks redraw only the line.
struct BrowserBottomChrome: View {
    @Bindable var speech: SpeechController
    /// Address-bar dictation (nil until the mic is first used).
    let dictation: AddressDictation?
    /// The page is saved in the Library (🔖 filled).
    let isSaved: Bool
    var onOpenReader: () -> Void
    /// 🎧: listen to the page now, or pause / resume it when it is what you hear.
    var onListen: () -> Void = {}
    var onSubmit: () -> Void
    var onMic: () -> Void
    /// 🔖: save the page to the Library, or remove it.
    var onToggleSave: () -> Void
    /// 🔖 held: *Save to Folder…*.
    var onSaveToFolder: () -> Void
    let menu: () -> MenuContext

    @Environment(ShellState.self) private var shell

    private var web: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }

    var body: some View {
        regularChrome
            .overlay(alignment: .top) { LoadProgressLine(web: web) }
    }

    /// Address field as main-pane chrome; clustered player + browse tools in the dock. The sidebar
    /// owns the Library swap.
    private var regularChrome: some View {
        VStack(spacing: 0) {
            SurfaceBand(
                session: search,
                cancelID: "addressCancel",
                onCancel: shell.endAddressSearch,
                begin: { search.begin(with: web.currentURL?.absoluteString ?? "") }
            ) { focus in
                BrowseAddressField(speech: speech, dictation: dictation, onOpenReader: onOpenReader, onListen: onListen,
                                   onSubmit: onSubmit, onMic: onMic, focus: focus)
            }
            if !search.isActive {
                ClusteredPlayerDock(speech: speech, isCovered: shell.reader != nil,
                                    trailingTools: AnyView(toolbar))
            }
        }
    }

    // MARK: - Toolbar

    /// `[‹][›][🔖][🕘][⋯]`, slot for slot the Library's `[‹][›][＋][🕘][⋯]`. Reader is the icon in
    /// the address field and the ⋯ panel's focus button; a new search is a tap on the field.
    private var toolbar: some View {
        BottomToolbarLayout {
            BandToolbarButton(systemImage: Icons.back, label: Verbs.back,
                              identifier: "browseBack", action: web.goBack)
                .disabled(!web.canGoBack)
                .toolbarSlot(0)
            BandToolbarButton(systemImage: Icons.forward, label: Verbs.forward,
                              identifier: "browseForward", action: web.goForward)
                .disabled(!web.canGoForward)
                .toolbarSlot(1)
            SaveToggleButton(isSaved: isSaved, isBusy: shell.busy == .save, identifier: "browseSave",
                             onToggle: onToggleSave, onSaveToFolder: onSaveToFolder)
                .disabled(!web.hasPage || shell.busy != nil)
                .toolbarSlot(2)
            BandToolbarButton(systemImage: Icons.history, label: Verbs.history,
                              identifier: "browseHistory") { shell.present(.history) }
                .toolbarSlot(3)
            MoreMenuButton(id: "browseMore", menu: menu)
                .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
    }
}

/// The address `TextField` inside the field capsule.
private struct TextFieldBox: View {
    @Binding var text: String
    let isDictating: Bool
    let focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField(isDictating && text.isEmpty ? "Listening…" : "Search or enter address", text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.webSearch)
            .submitLabel(.go)
            .focused(focus)
            .onSubmit(onSubmit)
            .accessibilityIdentifier("addressField")
    }
}

/// What sits at the address field's end while searching: ⊗ (with text), then 🎤.
private struct AddressAccessories: View {
    @Binding var text: String
    let searching: Bool
    let isDictating: Bool
    let isListening: Bool
    let onMic: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if searching { ClearBox(text: $text) }
            MicBox(shown: searching, isDictating: isDictating, isListening: isListening, action: onMic)
        }
    }
}

/// ⊗ inside the field's end while searching and there is text: empties it, the keyboard stays.
private struct ClearBox: View {
    @Binding var text: String

    var body: some View {
        if !text.isEmpty {
            Button { text = "" } label: {
                Image(systemName: Icons.clearText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fieldControlFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear text")
            .accessibilityIdentifier("addressClear")
        }
    }
}

/// 🎤, only while searching.
private struct MicBox: View {
    let shown: Bool
    let isDictating: Bool
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        if shown {
            Button(action: action) {
                Image(systemName: isDictating ? Icons.dictating : Icons.dictate)
                    .foregroundStyle(isDictating ? Palette.accent : Palette.secondaryInk)
                    .symbolEffect(.variableColor.iterative, isActive: isListening)
                    .fieldControlFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDictating ? "Stop dictation" : "Dictate")
            .accessibilityIdentifier("addressMic")
        }
    }
}

/// Thin page-load progress on the chrome's top edge (no layout shift while loading). Reads the
/// web view's progress itself, so its ticks don't re-run the chrome or the browser. Follow's
/// chapter preview draws it along its header's foot.
struct LoadProgressLine: View {
    let web: WebViewStore

    var body: some View {
        if web.isLoading && web.hasPage {
            GeometryReader { g in
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: g.size.width * max(0.08, min(1, web.progress)), height: 2)
            }
            .frame(height: 2)
            .allowsHitTesting(false)
        }
    }
}

/// The browser's address field: 📄 on readable pages (it toggles the page's reader view in compact
/// width), the page's address, and at the trailing end 🎧 in the regular band or ↻ / ✕ in the compact
/// chrome host (`compact`; play and pause live in the chrome's own button there). 🎤 while searching.
struct BrowseAddressField: View {
    @Bindable var speech: SpeechController
    /// Address-bar dictation (nil until the mic is first used).
    let dictation: AddressDictation?
    var onOpenReader: () -> Void
    /// The compact chrome host's field: ↻ / ✕ in place of 🎧.
    var compact = false
    /// 🎧 (regular width): listen to the page now, or pause / resume it when it is what you hear.
    var onListen: () -> Void = {}
    /// ↻ / ✕ (compact width).
    var onReload: () -> Void = {}
    var onSubmit: () -> Void
    var onMic: () -> Void
    let focus: FocusState<Bool>.Binding

    @Environment(ShellState.self) private var shell

    private var web: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }
    private var isDictating: Bool { dictation?.isActive == true }

    /// The page's canonical URL when 🎧 can listen to it (a readable page).
    private var listenTarget: ListenTarget? {
        guard !search.isActive, web.hasPage, web.isReaderable, let url = web.currentURL else { return nil }
        return .webPage(canonicalURL: ArticleIdentity.canonicalURLString(from: url))
    }

    private var listenState: PlayState? {
        compact ? nil : listenTarget.map(speech.playState(of:))
    }

    private var reloadButton: Field.ReloadButton? {
        guard compact, !search.isActive, web.hasPage else { return nil }
        return web.isLoading ? .stop : .reload
    }

    /// Aa while the compact chrome shows the page's reader view and no search is open.
    private var appearanceBinding: Binding<Bool>? {
        guard compact, !search.isActive, shell.pageReader != nil else { return nil }
        return Bindable(shell).readerAppearanceOpen
    }

    private typealias Field = AddressField<TextFieldBox, AddressAccessories>

    private var readerButton: Field.ReaderButton {
        if search.isActive { return .searching }
        if shell.busy == .reader { return .extracting }
        if compact && shell.pageReader != nil { return .showing }
        return web.hasPage && web.isReaderable ? .available : .hidden
    }

    var body: some View {
        @Bindable var search = search
        Field(reader: readerButton, listen: listenState, reload: reloadButton, appearance: appearanceBinding, onOpenReader: onOpenReader,
              onListen: onListen, onReload: onReload) {
            TextFieldBox(text: $search.text, isDictating: isDictating, focus: focus, onSubmit: onSubmit)
        } accessory: {
            AddressAccessories(text: $search.text, searching: search.isActive, isDictating: isDictating,
                               isListening: dictation?.isListening == true, onMic: onMic)
        }
        .overlay {
            if isDictating {
                Capsule().strokeBorder(Palette.accent, lineWidth: 1.5)
            }
        }
        .animation(Motion.snappy, value: listenState)
        // Aa goes while a search is open: its panel closes with it, and stays closed when Aa returns.
        .onChange(of: search.isActive) { _, active in if active { shell.readerAppearanceOpen = false } }
    }
}
