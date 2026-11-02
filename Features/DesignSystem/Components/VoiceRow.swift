import SwiftUI

/// A voice in the Voice picker, drawn as iOS's own Voice screen (Settings › Accessibility ›
/// Spoken Content › Voices) draws one: its sample's ▶ at the leading edge, its name over its size,
/// and one trailing mark.
///
/// ```
/// ( ▶ )  Heart                                   ✓      the voice in use
///        0.5 MB
/// ( ▶ )  Bella                                          on the device: the size it takes
///        0.5 MB
/// ( ▶ )  Emma                                    ⤓      not downloaded: tap to download
///        164 MB                                          (what it downloads)
/// ( ▶ )  Puck                                    ◜      starting (the spinning arc)
///        164 MB
/// ( ▶ )  Fable                                   ◔■     downloading: ■ stops it
///        164 MB
/// ( ▶ )  Puck                                    ⤓      failed: tap to try again
///        Couldn't download                               (in the destructive colour)
/// ```
///
/// Every row is two lines in every state (the failure takes the size's place), so a row's height
/// never changes and all rows look alike; VoiceOver reads the second line with the name. ✓ means
/// the voice speaks now, so it shows only on a voice on the device: the voice in use that isn't
/// (removed since, or its library's model missing) shows ⤓ and its size like any other, and
/// VoiceOver still calls it selected; a tap downloads it, and the ✓ comes back once it is there.
/// A tap on the row (or ⤓) is `onPick`; the ring's tap is `onStop`, which stops the download for
/// everyone waiting on it, listening included (its VoiceOver hint says so). In Edit a row whose
/// download can go leads with ⊖, which shows *Remove* in place of its mark (`onRemove`, the
/// swipe's action too); the row never leaves the list, so the List never thinks it was deleted.
/// Every control's hit area is `Control.tap`. ⤓, the arc and the ring are `DownloadMark`, the app's
/// one download look.
struct VoiceRow: View {
    /// Whether the voice is on the device, and what its row says about it.
    enum Download: Equatable {
        /// On the device, taking `size` there (nil: unknown, one line).
        case onDevice(size: String?)
        /// Choosing it downloads `size` ("0.5 MB").
        case notDownloaded(size: String)
        /// `fraction` once the size is known, nil while it starts or checks.
        case downloading(fraction: Double?, size: String)
        /// The last try failed; a tap tries again.
        case failed
    }

    let name: String
    let download: Download
    /// The voice in use (the ✓ once it is on the device).
    let selected: Bool
    /// Its sample is playing (▶ shows ■).
    var previewing = false
    /// It has a sample (else its ▶ is dimmed).
    var hasPreview = true
    /// Its row's identifier; ▶, ⤓ and the ring take it with a suffix.
    let accessibilityID: String
    /// The screen is in Edit: a removable row (`onRemove`) leads with ⊖.
    var editing = false
    let onPick: () -> Void
    var onPreview: () -> Void = {}
    var onStop: () -> Void = {}
    /// Removes its download (asking first when it must); nil: it can't be removed now.
    var onRemove: (() -> Void)?
    /// ⊖ was tapped: *Remove* shows in place of the trailing mark. The list holds it, so one row
    /// shows it at a time and leaving Edit hides it.
    var removeShown: Binding<Bool> = .constant(false)
    private var revealed: Bool { removeShown.wrappedValue }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the name starts: past the ▶'s column. A row that leads into voice rows lines up here.
    static let nameInset = Control.tap + Spacing.xs

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // In Edit every row takes ⊖'s column, as iOS indents a list in Edit, so names stay lined up.
            if editing {
                if onRemove != nil {
                    removeControl
                } else {
                    Color.clear.frame(width: Control.tap, height: Control.tap).accessibilityHidden(true)
                }
            }
            previewButton
            Button(action: onPick) {
                SymbolRow(name, subtitle: detail, reservesDetail: true, symbol: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(downloadingValue)
            if revealed, let onRemove {
                removeButton(onRemove)
            } else if hasMark {
                trailing
                    .frame(width: RowMetrics.accessorySlot, height: RowMetrics.accessorySlot)
            }
        }
        // The trailing mark in every row's accessory slot (`RowMetrics`): its glyph ends where the card's
        // text does.
        .listRowInsets(EdgeInsets(top: 0, leading: RowMetrics.edgeInset, bottom: 0,
                                  trailing: hasMark && !revealed ? RowMetrics.accessoryTrailing : RowMetrics.edgeInset))
    }

    /// Edit's ⊖: shows (or hides) *Remove*, as iOS's delete control. The row stays in the list
    /// whatever happens next: only its download goes, after its question.
    private var removeControl: some View {
        Button {
            withAnimation(reduceMotion ? Motion.fadeIn : Motion.snappy) { removeShown.wrappedValue.toggle() }
        } label: {
            Image(systemName: Icons.removeControl)
                .glyphSize(Glyph.regular)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Palette.onDestructive, Palette.destructive)
                .rotationEffect(.degrees(revealed ? -90 : 0))
                .frame(minWidth: Control.tap, minHeight: Control.tap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Remove \(name)"))
        .accessibilityHint(String(localized: "Shows Remove."))
        .accessibilityIdentifier("\(accessibilityID)-removeControl")
        .transition(.opacity)
    }

    private func removeButton(_ onRemove: @escaping () -> Void) -> some View {
        Button {
            removeShown.wrappedValue = false
            onRemove()
        } label: {
            Text(Verbs.remove)
                .typeStyle(.row)
                .foregroundStyle(Palette.onDestructive)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: Control.small)
                .background(Capsule().fill(Palette.destructive))
                .frame(minHeight: Control.tap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityID)-remove")
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    /// A row without a mark (on the device, not in use) gives the name the room, so a long one
    /// at the accessibility sizes doesn't break inside a word for an empty column.
    private var hasMark: Bool {
        if case .onDevice = download { return selected }
        return true
    }

    private var detail: DetailPart? {
        switch download {
        case .onDevice(let size): size.map { DetailPart($0) }
        case .notDownloaded(let size), .downloading(_, let size): DetailPart(size)
        case .failed: DetailPart(String(localized: "Couldn’t download"), isAlert: true)
        }
    }

    private var downloadingValue: String {
        guard case .downloading(let fraction, _) = download else { return "" }
        guard let fraction else { return String(localized: "Downloading") }
        return String(localized: "Downloading, \(Int((fraction * 100).rounded())) percent")
    }

    /// Always the ▶'s column, so every row's name starts in the same place; a voice without a
    /// sample shows its ▶ dimmed (it can't run), never an empty gap.
    private var previewButton: some View {
        Button(action: onPreview) {
            Image(systemName: previewing ? Icons.previewStop : Icons.previewPlay)
                .glyphSize(Glyph.large)
                .foregroundStyle(Palette.accent)
                .frame(minWidth: Control.tap, minHeight: Control.tap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasPreview)
        .opacity(hasPreview ? 1 : Palette.disabledOpacity)
        .accessibilityLabel(previewing ? String(localized: "Stop Sample")
                            : String(localized: "Play Sample of \(name)"))
        .accessibilityIdentifier("\(accessibilityID)-preview")
    }

    @ViewBuilder
    private var trailing: some View {
        switch download {
        case .downloading(let fraction, _):
            Button(action: onStop) {
                DownloadMark(state: fraction.map { .progress($0) } ?? .waiting, stops: true)
                    .frame(minWidth: Control.tap, minHeight: Control.tap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stop Downloading \(name)"))
            .accessibilityHint(String(localized: "Listening that waits for it stops too."))
            .accessibilityIdentifier("\(accessibilityID)-stop")
        case .onDevice where selected:
            Image(systemName: Icons.checkmark)
                .glyphSize(Glyph.regular, weight: .semibold)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
        case .notDownloaded, .failed:
            Button(action: onPick) {
                DownloadMark(state: .idle)
                    .frame(minWidth: Control.tap, minHeight: Control.tap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Download \(name)"))
            .accessibilityIdentifier("\(accessibilityID)-download")
        case .onDevice:
            EmptyView()
        }
    }
}

#if DEBUG
struct VoiceRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("in use, on the device, not downloaded") {
                VStack(spacing: 0) {
                    VoiceRow(name: "Heart", download: .onDevice(size: "0.5 MB"), selected: true, accessibilityID: "a", onPick: {})
                    VoiceRow(name: "Bella", download: .onDevice(size: "0.5 MB"), selected: false, previewing: true,
                             accessibilityID: "b", onPick: {})
                    VoiceRow(name: "Emma", download: .notDownloaded(size: "0.5 MB"), selected: false,
                             accessibilityID: "c", onPick: {})
                }
            }
            PreviewState("starting, downloading, failed") {
                VStack(spacing: 0) {
                    VoiceRow(name: "Puck", download: .downloading(fraction: nil, size: "164 MB"), selected: false,
                             accessibilityID: "d", onPick: {})
                    VoiceRow(name: "Fable", download: .downloading(fraction: 0.4, size: "164 MB"), selected: false,
                             accessibilityID: "e", onPick: {})
                    VoiceRow(name: "Emma", download: .failed, selected: false, accessibilityID: "f", onPick: {})
                }
            }
            PreviewState("Edit: ⊖ on the rows whose download can go") {
                VStack(spacing: 0) {
                    VoiceRow(name: "Bella", download: .onDevice(size: "0.5 MB"), selected: false,
                             accessibilityID: "h", editing: true, onPick: {}, onRemove: {})
                    VoiceRow(name: "Emma", download: .onDevice(size: "0.5 MB"), selected: false,
                             accessibilityID: "j", editing: true, onPick: {}, onRemove: {},
                             removeShown: .constant(true))
                    VoiceRow(name: "Heart", download: .onDevice(size: "0.5 MB"), selected: true,
                             accessibilityID: "i", editing: true, onPick: {})
                }
            }
            PreviewState("in use, not on the device (no ✓ until it is)") {
                VoiceRow(name: "Heart", download: .notDownloaded(size: "163 MB"), selected: true,
                         accessibilityID: "g", onPick: {})
            }
        }
    }
}

#Preview("VoiceRow · light", traits: .sizeThatFitsLayout) { VoiceRowGallery().previewVariant(.light) }
#Preview("VoiceRow · dark", traits: .sizeThatFitsLayout) { VoiceRowGallery().previewVariant(.dark) }
#Preview("VoiceRow · AX5", traits: .sizeThatFitsLayout) { VoiceRowGallery().previewVariant(.largestText) }
#endif
