import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// *Edit Details* (`ShellSheet.folderDetails`): a folder's, book's or series' name, author and
/// cover, from the folder's ⋯ or its row's long-press menu. *Cancel* leaves it as it was; *Save*
/// writes all three in one edit (`LibraryStore.setDetails`) and closes. A picked picture is made
/// small first (`CoverThumbnail`, as a book's cover is on import). A plain folder given a cover or
/// an author shows a book's header and its cover on its row, and stays a plain folder.
///
/// ```
/// Cancel            Edit Details              Save
///                    ╭──────╮
///                    │cover │
///                    ╰──────╯
/// Name
///  Tide Tables
/// Author
///  A. Writer
/// Cover
///  🖼  Choose from Photos
///  📁  Choose from Files
///  🗑  Remove Cover                      (with a cover)
/// ```
struct FolderDetailsSheet: View {
    let folderID: UUID

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @State private var name = ""
    @State private var byline = ""
    @State private var cover: Data?
    @State private var usesBookLabels = false
    @State private var isLoaded = false
    @State private var photo: PhotosPickerItem?
    @State private var isPickingPhoto = false
    @State private var isPickingFile = false
    /// A picked picture being read and made small: Save waits for it.
    @State private var isPreparingCover = false

    @ScaledMetric(relativeTo: .title3) private var scaledCoverWidth: CGFloat = 96
    private var coverWidth: CGFloat { BottomChrome.grown(scaledCoverWidth, from: 96) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EmptyView()
                } header: {
                    coverPreview
                        .listHeader()
                }
                field(Verbs.name, text: $name, prompt: Verbs.name, id: "detailsName")
                field(String(localized: "Author"), text: $byline, prompt: String(localized: "Optional"), id: "detailsAuthor")
                Section {
                    Toggle(String(localized: "Book"), isOn: $usesBookLabels)
                        .typeStyle(.row)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: BottomChrome.minTapTarget)
                        .accessibilityIdentifier("detailsBookToggle")
                        .accessibilityHint(String(localized: "Calls pages \u{201C}chapters\u{201D}"))
                } header: {
                    SectionHeader(title: String(localized: "Labels"))
                        .listHeader()
                }
                .listRowInsets(EdgeInsets())
                .listCard()
                Section {
                    choice(String(localized: "Choose from Photos"), Icons.photos, id: "detailsCoverPhotos") {
                        isPickingPhoto = true
                    }
                    choice(String(localized: "Choose from Files"), Icons.files, id: "detailsCoverFiles") { pickFile() }
                    if cover != nil {
                        choice(String(localized: "Remove Cover"), Icons.delete, id: "detailsRemoveCover") {
                            withAnimation(Motion.snappy) { cover = nil }
                        }
                    }
                } header: {
                    SectionHeader(title: String(localized: "Cover"))
                        .listHeader()
                }
                .listRowInsets(EdgeInsets())
                .listCard()
            }
            .cardListStyle()
            .navigationTitle(Verbs.title(Verbs.editDetails))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.cancel, placement: .cancellationAction, identifier: "detailsCancel") {
                    shell.sheet = nil
                }
                SheetBarButton(Verbs.save, placement: .confirmationAction, identifier: "detailsSave",
                               isDisabled: isPreparingCover) { save() }
            }
        }
        .sheetToastLayer()
        .photosPicker(isPresented: $isPickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            useCover { try await item.loadTransferable(type: Data.self) }
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            useCover { try Self.read(url) }
        }
        .onAppear(perform: load)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folderDetailsSheet")
    }

    // MARK: - Pieces

    /// The cover as it will show, or the letter tile a folder without one shows.
    private var coverPreview: some View {
        ArtworkTile(image: cover.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)), letter: name,
                    size: coverWidth, isCover: true)
            .floatingShadow(opacity: 0.15)
            .overlay {
                if isPreparingCover { ProgressView() }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
            .accessibilityElement()
            .accessibilityLabel(cover == nil ? "No cover" : "Cover")
            .accessibilityIdentifier("detailsCover")
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, id: String) -> some View {
        Section {
            TextField(prompt, text: text)
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: BottomChrome.minTapTarget)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        } header: {
            SectionHeader(title: title)
                .listHeader()
        }
        .listRowInsets(EdgeInsets())
        .listCard()
    }

    private func choice(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SymbolRow(title, symbol: symbol)
                .padding(.horizontal, Spacing.m)
        }
        .buttonStyle(.plain)
        .disabled(isPreparingCover)
        .accessibilityIdentifier(id)
    }

    // MARK: - Doing

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let folder = library.folder(id: folderID) else {
            shell.sheet = nil
            return
        }
        name = folder.name
        byline = folder.byline ?? ""
        cover = folder.coverData
        usesBookLabels = folder.kind == .book
    }

    /// *Choose from Files*: the Files picker.
    private func pickFile() {
        isPickingFile = true
    }

    /// Reads the picked picture and makes it a cover thumbnail, off the main thread. One that
    /// can't be read changes nothing, and a toast says so.
    private func useCover(_ read: @escaping @Sendable () async throws -> Data?) {
        isPreparingCover = true
        Task {
            let thumbnail = await Task.detached(priority: .userInitiated) {
                (try? await read()).flatMap { CoverThumbnail.make(from: $0) }
            }.value
            isPreparingCover = false
            if let thumbnail {
                withAnimation(Motion.snappy) { cover = thumbnail }
            } else {
                shell.showToast(ShellToast(message: String(localized: "Couldn’t use that picture"),
                                           systemImage: Icons.warning))
            }
        }
    }

    /// A file from the Files picker, read under its security-scoped access.
    private static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// Saves the three together; the sheet stays up, under its toast, when the save fails.
    private func save() {
        guard let folder = library.folder(id: folderID) else {
            shell.sheet = nil
            return
        }
        let newKind: FolderKind = usesBookLabels ? .book : .plain
        guard shell.attempt(String(localized: "Couldn’t save the details"), {
            try library.setDetails(of: folder, name: name, byline: byline, cover: cover, kind: newKind)
        }) != nil else { return }
        shell.sheet = nil
    }
}
