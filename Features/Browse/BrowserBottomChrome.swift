import SwiftUI

/// The browser's bottom chrome (`SearchSessionChrome` + the shared `BottomChrome` look):
///
/// ```
/// [ ▶︎ Now playing title ━━━━━━━──────   ⏸ ]   ← mini player (idle, while something is loaded)
/// [ 📄 address …                      (🎤) ]   ← reader icon when readable; 🎤 only while searching
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
    var onSubmit: () -> Void
    var onMic: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenNowPlaying: () -> Void
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
            // Under the reader overlay the reader is the player; the bar takes over as it leaves.
            if shell.readerArticle == nil {
                MiniPlayerBar(speech: speech, onOpen: onOpenNowPlaying)
                    .padding(.bottom, Spacing.xxs)
            }
        } field: { focus in
            addressField(focus)
        } toolbar: {
            toolbar
        }
        .overlay(alignment: .top) { LoadProgressLine(web: web) }
    }

    // MARK: - Address field

    private func addressField(_ focus: FocusState<Bool>.Binding) -> some View {
        @Bindable var search = search
        return HStack(spacing: Spacing.xs) {
            leading

            TextField(isDictating && search.text.isEmpty ? "Listening…" : "Search or enter address",
                      text: $search.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused(focus)
                .onSubmit(onSubmit)
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("addressField")

            if search.isActive {
                micButton
            }
        }
        .bottomChromeField(leading: Spacing.s, trailing: search.isActive ? Spacing.xxs : Spacing.s)
        .overlay {
            if isDictating {
                Capsule().strokeBorder(Palette.accent, lineWidth: 1.5)
            }
        }
    }

    /// Leading slot: a spinner while extracting for the reader, the reader icon (Safari's
    /// page-format button) when the page is readable, the search glyph while searching, or an
    /// empty spacer.
    @ViewBuilder
    private var leading: some View {
        if search.isActive {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: Glyph.indicator)
                .accessibilityHidden(true)
        } else if shell.busy == .reader {
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
        } else if web.hasPage && web.isReaderable {
            Button(action: onOpenReader) {
                Image(systemName: "doc.plaintext")
                    .font(.body)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 30, height: 30)
                    .tapTarget(30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open in Reader")
            .accessibilityIdentifier("addressReader")
            .transition(.opacity)
        } else {
            Color.clear
                .frame(width: Glyph.indicator, height: Glyph.indicator)
                .accessibilityHidden(true)
        }
    }

    private var micButton: some View {
        Button(action: onMic) {
            Image(systemName: isDictating ? "waveform" : "mic")
                .foregroundStyle(isDictating ? Palette.accent : Palette.secondaryInk)
                .symbolEffect(.variableColor.iterative, isActive: dictation?.isListening == true)
                .fieldControlFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDictating ? "Stop dictation" : "Dictate")
        .accessibilityIdentifier("addressMic")
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
