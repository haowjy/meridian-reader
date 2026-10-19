import SwiftUI

/// The browser's bottom chrome: the band it shares with the Library (`SurfaceBand`):
///
/// ```
/// [📚] ╭ Now Playing bar ──────────────────────╮   ← 📚 the Library; the bar always there
/// ( 📄 address …                          🎧 )   ← 📄 / 🎧 on readable pages; 🎤 while searching
/// [ ‹ ]   [ › ]   [ 🔖 ]   [ 🕘 ]   [ ⋯ ]      ← five slots; step aside while searching
/// ```
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
    var onListen: () -> Void
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
    private var isDictating: Bool { dictation?.isActive == true }

    var body: some View {
        SurfaceBand(
            swap: .init(systemImage: Icons.library, label: Verbs.library,
                        hint: String(localized: "Show the Library"), identifier: "browseLibrary",
                        action: shell.openLibrary),
            session: search,
            cancelID: "addressCancel",
            onCancel: shell.endAddressSearch,
            // Like Safari: the session starts with the page's full address, selected.
            begin: { search.begin(with: web.currentURL?.absoluteString ?? "") },
            isBarCovered: shell.reader != nil
        ) { focus in
            addressField(focus)
        } toolbar: {
            toolbar
        }
        .overlay(alignment: .top) { LoadProgressLine(web: web) }
        .animation(Motion.snappy, value: listenState)
    }

    // MARK: - Address field

    /// The page's canonical URL when 🎧 can listen to it (a readable page).
    private var listenTarget: ListenTarget? {
        guard !search.isActive, web.hasPage, web.isReaderable, let url = web.currentURL else { return nil }
        return .webPage(canonicalURL: ArticleIdentity.canonicalURLString(from: url))
    }

    private var listenState: PlayState? {
        listenTarget.map(speech.playState(of:))
    }

    private typealias Field = AddressField<TextFieldBox, MicBox>

    private var readerButton: Field.ReaderButton {
        if search.isActive { return .searching }
        if shell.busy == .reader { return .extracting }
        return web.hasPage && web.isReaderable ? .available : .hidden
    }

    private func addressField(_ focus: FocusState<Bool>.Binding) -> some View {
        @Bindable var search = search
        return Field(reader: readerButton, listen: listenState, onOpenReader: onOpenReader, onListen: onListen) {
            TextFieldBox(text: $search.text, isDictating: isDictating, focus: focus, onSubmit: onSubmit)
        } accessory: {
            MicBox(shown: search.isActive, isDictating: isDictating,
                   isListening: dictation?.isListening == true, action: onMic)
        }
        .overlay {
            if isDictating {
                Capsule().strokeBorder(Palette.accent, lineWidth: 1.5)
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
