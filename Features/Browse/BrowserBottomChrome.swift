import SwiftUI

/// The browser's bottom chrome (`SearchSessionChrome` + the shared `BottomChrome` look):
///
/// ```
/// ╭ Now Playing bar ───────────────────────╮   ← what you hear (once something has played)
/// ( 📄 address …                        🎧 )   ← 📄 / 🎧 on readable pages; 🎤 while searching
/// [ ‹ ]   [ › ]   [ 🔍 ]   [ 📚 ]   [ ⋯ ]    ← five slots; steps aside while searching
/// ```
///
/// A thin load-progress line sits on its top edge. It is its own view so `estimatedProgress`
/// ticks redraw only the line.
struct BrowserBottomChrome: View {
    @Bindable var speech: SpeechController
    /// Address-bar dictation (nil until the mic is first used).
    let dictation: AddressDictation?
    var onOpenReader: () -> Void
    /// 🎧: listen to the page now, or pause / resume it when it is what you hear.
    var onListen: () -> Void
    var onSubmit: () -> Void
    var onMic: () -> Void
    var onOpenLibrary: () -> Void
    let menu: () -> MenuContext

    @Environment(ShellState.self) private var shell

    private var web: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }
    private var isDictating: Bool { dictation?.isActive == true }

    var body: some View {
        SearchSessionChrome(
            session: search,
            cancelID: "addressCancel",
            onCancel: shell.endAddressSearch,
            // Like Safari: the session starts with the page's full address, selected.
            beginText: { web.currentURL?.absoluteString ?? "" }
        ) {
            NowPlayingBarView(speech: speech, isCovered: shell.reader != nil || shell.isInLibrary)
                .padding(.bottom, Spacing.xxs)
        } field: { focus in
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

    /// `[‹][›][Search][Library][⋯]` in the shared five-slot grid. Reader is the icon in the address
    /// field and the ⋯ panel's focus button; Bookmarks / Saved / History live in the ⋯ panel and
    /// on the start page. Slot 4 is the Library↔Browser swap (the library shows 🌐 there).
    private var toolbar: some View {
        BottomToolbarLayout {
            button("chevron.backward", label: "Back", id: "browseBack", action: web.goBack)
                .disabled(!web.canGoBack)
            button("chevron.forward", label: "Forward", id: "browseForward", action: web.goForward)
                .disabled(!web.canGoForward)
            // One tap to a new search: the field, focused and empty (Recent Searches); ✕ restores
            // the page's address.
            button("magnifyingglass", label: "Search", id: "browseSearch") { search.begin() }
            button("books.vertical", label: "Library", id: "browseLibrary", action: onOpenLibrary)
            MoreMenuButton(id: "browseMore", isBusy: shell.busy == .save, menu: menu)
        }
        // Tint, not foregroundStyle: a foreground style overrides the dimming SwiftUI gives
        // disabled buttons, so ‹ / › with no history would look tappable.
        .tint(Palette.ink)
    }

    private func button(_ systemImage: String, label: String, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).toolbarIconFrame()
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
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
                Image(systemName: isDictating ? "waveform" : "mic")
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
/// web view's progress itself, so its ticks don't re-run the chrome or the browser.
private struct LoadProgressLine: View {
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
