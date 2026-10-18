import SwiftUI

/// A followed story's status line, tapped (`ShellSheet.following`): where it is read from, when it
/// was and will be checked, how far its chapters' text has come, *Check Now*, and *Unfollow*
/// (*Follow Again* once unfollowed). Unfollowing stops the daily check only: every chapter added
/// stays, and their text is still fetched.
///
/// ```
///                 Following                    ( Done )
/// royalroad.com/fiction/40512
/// Last checked                       today 8:02 AM
/// Next check                      tomorrow 8:02 AM
/// Chapter text                    109 of 109 fetched
/// Last new chapters                  today · 2 added
/// ↻ Check Now
/// 📡̸ Unfollow
/// Each check reads the whole table of contents, so no chapter is missed after a long gap. …
/// ```
struct FollowingSheet: View {
    let folderID: UUID

    @Environment(LibraryStore.self) private var library
    @Environment(FollowCenter.self) private var follow
    @Environment(ShellState.self) private var shell

    var body: some View {
        NavigationStack {
            Group {
                if let folder = library.folder(id: folderID), let state = folder.followState {
                    content(folder, state)
                } else {
                    Color.clear.onAppear { shell.sheet = nil }
                }
            }
            .navigationTitle(String(localized: "Following"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "followingDone") { shell.sheet = nil }
            }
        }
        .presentationDetents([.medium, .large])
        .sheetToastLayer()
        .accessibilityIdentifier("followingSheet")
    }

    private func content(_ folder: Folder, _ state: FollowState) -> some View {
        let progress = follow.progress(of: library.pages(in: folder))
        let checking = follow.checking.contains(folder.id)
        return List {
            Section {
                fact(String(localized: "Last checked"), state.lastCheckedAt.map { FollowText.when($0) } ?? "—")
                fact(String(localized: "Next check"), nextCheck(folder))
                fact(String(localized: "Chapter text"), chapterText(progress))
                fact(String(localized: "Last new chapters"), state.lastAddedAt.map {
                    String(localized: "\(FollowText.when($0)) · \(state.lastAddedCount) added")
                } ?? String(localized: "None yet"))
            } header: {
                Text(folder.contentsURL.map { ShellState.addressText(for: $0) } ?? "")
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .libraryHeader()
                    .accessibilityIdentifier("followingAddress")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.chrome)

            Section {
                action(Verbs.checkNow, Icons.reload, id: "followingCheckNow", busy: checking) {
                    Task { await follow.check(folder) }
                }
                .disabled(checking)
                if state.isFollowing {
                    action(Verbs.unfollow, Icons.unfollow, id: "followingUnfollow", tint: Palette.destructive) {
                        shell.attempt(String(localized: "Couldn’t unfollow")) { try library.setFollowing(folder, false) }
                    }
                } else {
                    action(Verbs.followAgain, Icons.follow, id: "followingFollowAgain") {
                        shell.attempt(String(localized: "Couldn’t follow again")) { try library.setFollowing(folder, true) }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let failure = follow.checkFailures[folder.id] {
                        Label(String(localized: "The last check failed: \(failure.message)."), systemImage: Icons.warning)
                            .foregroundStyle(Palette.caution)
                            .accessibilityIdentifier("followingCheckFailed")
                    }
                    Text("Each check reads the whole table of contents, so no chapter is missed after a long gap. Chapters you left out in Review stay out. Unfollowing stops the checks and keeps every chapter added.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                .typeStyle(.caption)
                .libraryFooter()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.chrome)
        }
        .libraryListStyle()
    }

    private func nextCheck(_ folder: Folder) -> String {
        guard let next = follow.nextCheck(of: folder) else { return String(localized: "Off") }
        return next <= .now ? String(localized: "When the app is next open") : FollowText.when(next)
    }

    /// "41 of 107 fetched", then "· 1 chapter couldn’t load" when one couldn't.
    private func chapterText(_ progress: FollowCenter.Progress) -> String {
        let fetched = String(localized: "\(progress.withText) of \(progress.chapters) fetched")
        guard progress.failed > 0 else { return fetched }
        return fetched + " · " + FollowText.couldNotLoad(progress.failed)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(title)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.s)
            Text(value)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
        .typeStyle(.row)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: BottomChrome.minTapTarget)
        .accessibilityElement(children: .combine)
    }

    private func action(_ title: String, _ symbol: String, id: String, tint: Color = Palette.ink, busy: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .frame(width: ListRow.leadingWidth)
                Text(title)
                    .typeStyle(.row)
                Spacer(minLength: 0)
                if busy { ProgressView().tint(Palette.accent) }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: BottomChrome.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
