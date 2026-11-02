import SwiftUI

/// A voice in the Voice picker, drawn as iOS's own Voice screen (Settings › Accessibility ›
/// Spoken Content › Voices) draws one: its sample's ▶ at the leading edge, its name, a second
/// line only while it isn't on the device (its download size, or that the download failed), and
/// one trailing mark.
///
/// ```
/// ( ▶ )  Heart                                   ✓      the voice in use
/// ( ▶ )  Bella                                          on the device
/// ( ▶ )  Emma                                    ⤓      not downloaded: tap to download
///        0.5 MB
/// ( ▶ )  Puck                                    ◌      starting (a spinner)
///        164 MB
/// ( ▶ )  Fable                                   ◔■     downloading: ■ stops it
///        164 MB
/// ( ▶ )  Puck                                    ⤓      failed: tap to try again
///        Couldn't download                               (in the destructive colour)
/// ```
///
/// ✓ means the voice speaks now, so it shows only on a voice on the device: the voice in use that
/// isn't (removed since, or its library's model missing) shows ⤓ and its size like any other,
/// and VoiceOver still calls it selected; a tap downloads it, and the ✓ comes back once it is
/// there. The size line stays while it downloads, so the row's height never changes then. A tap
/// on the row (or ⤓) is `onPick`; the ring's tap is `onStop`, which stops the download for
/// everyone waiting on it, listening included (its VoiceOver hint says so). Every control's hit
/// area is `Control.tap`.
struct VoiceRow: View {
    /// Whether the voice is on the device, and what its row says about it.
    enum Download: Equatable {
        case onDevice
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
    /// It has a sample (else the ▶'s column stays empty, so names line up).
    var hasPreview = true
    /// Its row's identifier; ▶, ⤓ and the ring take it with a suffix.
    let accessibilityID: String
    let onPick: () -> Void
    var onPreview: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.xs) {
            previewButton
            Button(action: onPick) {
                SymbolRow(name, subtitle: detail, symbol: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(downloadingValue)
            trailing
                .frame(minWidth: Control.tap, minHeight: Control.tap)
        }
    }

    private var detail: DetailPart? {
        switch download {
        case .onDevice: nil
        case .notDownloaded(let size), .downloading(_, let size): DetailPart(size)
        case .failed: DetailPart(String(localized: "Couldn’t download"), isAlert: true)
        }
    }

    private var downloadingValue: String {
        guard case .downloading(let fraction, _) = download else { return "" }
        guard let fraction else { return String(localized: "Downloading") }
        return String(localized: "Downloading, \(Int((fraction * 100).rounded())) percent")
    }

    @ViewBuilder
    private var previewButton: some View {
        if hasPreview {
            Button(action: onPreview) {
                Image(systemName: previewing ? Icons.previewStop : Icons.previewPlay)
                    .glyphSize(Glyph.large)
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: Control.tap, minHeight: Control.tap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previewing ? String(localized: "Stop Sample")
                                : String(localized: "Play Sample of \(name)"))
            .accessibilityIdentifier("\(accessibilityID)-preview")
        } else {
            Color.clear.frame(width: Control.tap, height: Control.tap).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch download {
        case .downloading(let fraction, _):
            Button(action: onStop) {
                DownloadProgressMark(fraction: fraction)
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
                Image(systemName: Icons.download)
                    .glyphSize(Glyph.regular)
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: Control.tap, minHeight: Control.tap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Download \(name)"))
            .accessibilityIdentifier("\(accessibilityID)-download")
        case .onDevice:
            Color.clear.accessibilityHidden(true)
        }
    }
}

/// A download in flight, as the App Store draws one: a thin accent arc spinning while it starts
/// (its size unknown; the system spinner with Reduce Motion), then a thin accent ring filling
/// clockwise round a small ■ (tap to stop).
struct DownloadProgressMark: View {
    let fraction: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        Group {
            if let fraction {
                ZStack {
                    Circle().stroke(Palette.track, lineWidth: Glyph.stroke)
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: Glyph.stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(Motion.standard, value: fraction)
                    Image(systemName: Icons.stop)
                        .font(.system(size: Glyph.slot * 0.33))
                        .foregroundStyle(Palette.accent)
                }
            } else if reduceMotion {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Palette.accent)
            } else {
                Circle()
                    .trim(from: 0, to: 0.8)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: Glyph.stroke, lineCap: .round))
                    .rotationEffect(.degrees(turned ? 360 : 0))
                    .onAppear { withAnimation(Motion.spin) { turned = true } }
            }
        }
        .frame(width: Glyph.slot, height: Glyph.slot)
    }
}

#if DEBUG
struct VoiceRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("in use, on the device, not downloaded") {
                VStack(spacing: 0) {
                    VoiceRow(name: "Heart", download: .onDevice, selected: true, accessibilityID: "a", onPick: {})
                    VoiceRow(name: "Bella", download: .onDevice, selected: false, previewing: true,
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
