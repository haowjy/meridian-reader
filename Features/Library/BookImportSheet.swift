import SwiftUI

/// The import sheet (`ShellSheet.importBook`): the book as read from its file, how far the import
/// is, and where the book goes. It can't be pulled away while it works; *Cancel* stops it.
///
/// ```
/// Cancel             Import Book             Import   ← Import: a downloaded book, before it starts
/// ╭──────╮  Pride and Prejudice
/// │cover │  Jane Austen
/// ╰──────╯  pride-and-prejudice.epub   61 chapters
/// ━━━━━━━━━━━━░░░░░░░  Reading chapters… 4 / 9
/// Add to
///  📁 Fiction                              Change    ← pushes the Move tree; works while it runs
/// The book becomes a folder inside Fiction, one chapter per section.
/// Chapters
///  Chapter 1
///  Chapter 2
///  Chapter 3
///  58 more
/// Skipped for listening: Title Page. Still there to read.
/// ```
///
/// A book already in the Library asks *Replace* or *Cancel* (decision D13); a refusal, or an
/// import or *Replace* whose save fails, says why in one line, with OK. Done, the sheet closes on
/// the book's screen. The shell's toast floats over the sheet and its *Add to* tree (a folder that
/// can't be made, another book arriving).
struct BookImportSheet: View {
    @Bindable var flow: BookImportFlow

    @Environment(ShellState.self) private var shell

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EmptyView()
                } header: {
                    header
                        .listHeader()
                }
                Section {
                    destinationRow
                        .listRowInsets(EdgeInsets())
                } header: {
                    SectionHeader(title: Verbs.addTo)
                        .listHeader()
                } footer: {
                    Text(destinationNote).listFooter()
                }
                .listCard()
                if let preview = flow.preview, !preview.chapterTitles.isEmpty {
                    chapters(preview)
                }
            }
            .cardListStyle()
            .navigationTitle(Verbs.title(Verbs.importBook))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(isPresented: $flow.isChoosingDestination) {
                MoveTreeList(current: flow.destinationID.map { .folder($0) } ?? .topLevel) {
                    flow.choose($0)
                } pickNewFolder: {
                    flow.chooseNewFolder(named: $0, in: $1, shell: shell)
                }
                .navigationTitle(Verbs.addTo)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("importAddToTree")
            }
        }
        .sheetToastLayer()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(flow.isWorking)
        .alert(alreadyInLibraryTitle, isPresented: isAsking) {
            Button(Verbs.cancel, role: .cancel) { flow.cancel() }
                .accessibilityIdentifier("importReplaceCancel")
            Button("Replace") { flow.replace() }
                .accessibilityIdentifier("importReplace")
        } message: {
            Text("Replace rebuilds its chapters in the same folder, and keeps your place where the chapters match.")
        }
        .alert(failure ?? "", isPresented: isFailing) {
            Button(Verbs.ok) { flow.acknowledgeFailure() }
                .accessibilityIdentifier("importFailureOK")
        }
        .onDisappear { flow.sheetGone() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importSheet")
    }

    // MARK: - Header

    /// The book as its folder's header will show it, with the import's progress bar under it.
    private var header: some View {
        VStack(spacing: Spacing.xs) {
            FolderHeader(style: .detailed(cover: cover), title: flow.title, detail: detail, source: source,
                         progressLabel: progress.map { [$0.label] } ?? []) {
                EmptyView()
            } more: {
                EmptyView()
            }
            if let progress {
                ProgressLine(fraction: progress.fraction, height: ProgressLine.barHeight, track: .groove)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("importHeader")
    }

    private var cover: Image? {
        flow.preview?.cover.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    /// The author once read, else the file.
    private var detail: [String] {
        [flow.preview?.byline ?? flow.fileName]
    }

    /// The file and its chapters, once read.
    private var source: [String] {
        guard let preview = flow.preview else { return [] }
        let chapters = String(localized: "\(preview.chapterCount) chapters")
        return preview.byline == nil ? [chapters] : [flow.fileName, chapters]
    }

    private var progress: (fraction: Double, label: String)? {
        guard case .working(let step) = flow.phase else { return nil }
        switch step {
        case .reading:
            return (0, String(localized: "Reading the EPUB…"))
        case .preparing(_, let done, let total):
            return (total > 0 ? Double(done) / Double(total) : 0, String(localized: "Reading chapters… \(done) / \(total)"))
        case .storing:
            return (1, String(localized: "Saving the folder…"))
        }
    }

    // MARK: - Add to

    private var destinationName: String {
        if flow.isDestinationGone { return String(localized: "Deleted folder") }
        return flow.destination?.name ?? Verbs.library
    }

    private var destinationRow: some View {
        Button { flow.isChoosingDestination = true } label: {
            SymbolRow(destinationName) {
                Image(systemName: flow.destinationID == nil ? Icons.library : Icons.folder)
                    .foregroundStyle(Palette.accent)
            } trailing: {
                if !flow.isReplacing {
                    Text("Change")
                        .typeStyle(.row)
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .buttonStyle(.plain)
        .disabled(!flow.canChangeDestination)
        .accessibilityLabel("\(Verbs.addTo) \(destinationName)")
        .accessibilityHint(flow.isReplacing ? "" : "Choose another folder")
        .accessibilityIdentifier("importChange")
    }

    private var destinationNote: String {
        if flow.isReplacing { return String(localized: "Replace keeps the folder where it is.") }
        if flow.isDestinationGone {
            return String(localized: "The folder chosen for this import was deleted. Choose another, or the import stops.")
        }
        guard let folder = flow.destination else {
            return String(localized: "The EPUB becomes a folder in the Library, one chapter per section.")
        }
        return String(localized: "The EPUB becomes a folder inside \(folder.name), one chapter per section.")
    }

    // MARK: - Chapters

    /// The first chapters that play, how many more, and what's skipped.
    private func chapters(_ preview: BookImportPreview) -> some View {
        let shown = Array(preview.chapterTitles.prefix(3))
        let more = preview.chapterCount - preview.skippedTitles.count - shown.count
        return Section {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, title in
                ListRow(kind: .chapter, title: title)
            }
            if more > 0 {
                Text("\(more) more")
                    .typeStyle(.row)
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, Spacing.m)
                    .frame(maxWidth: .infinity, minHeight: BottomChrome.minTapTarget, alignment: .leading)
            }
        } header: {
            SectionHeader(title: Verbs.chapters)
                .listHeader()
        } footer: {
            if !preview.skippedTitles.isEmpty {
                Text(String(localized: "Skipped for listening: \(Self.list(preview.skippedTitles)). Still there to read."))
                    .listFooter()
            }
        }
        .listRowInsets(EdgeInsets())
        .listCard()
    }

    /// "Title Page, Licence and 2 more".
    private static func list(_ titles: [String]) -> String {
        let shown = titles.prefix(3).joined(separator: ", ")
        return titles.count > 3 ? String(localized: "\(shown) and \(titles.count - 3) more") : shown
    }

    // MARK: - Toolbar and questions

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        SheetBarButton(Verbs.cancel, placement: .cancellationAction, identifier: "importCancel") { flow.cancel() }
        if flow.phase == .ready {
            SheetBarButton(Verbs.import, placement: .confirmationAction, identifier: "importStart") {
                flow.startImport()
            }
        }
    }

    private var alreadyInLibraryTitle: String {
        String(localized: "“\(flow.title)” is already in the Library")
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { if case .alreadyInLibrary = flow.phase { true } else { false } }, set: { _ in })
    }

    private var failure: String? {
        if case .failed(let message) = flow.phase { message } else { nil }
    }

    private var isFailing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { _ in })
    }
}
