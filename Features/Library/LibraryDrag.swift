import SwiftUI
import UniformTypeIdentifiers

/// Drag to file and to reorder, without Edit (decision D15). A long press lifts a row: its menu,
/// which the press opened, goes as the row lifts (iOS's own handover between the two). Let go
/// on a folder row to file it there, or between rows to place it.
///
/// - **Onto a folder row**: filed at the end of that folder, as *Move to…* does, with the same
///   refusals (`LibraryStore.moveRefusal`). A folder that takes the row is highlighted
///   (`ListRow.isDropTarget`), a book or series as any other (decision D19); a folder dragged
///   over itself or a folder inside it shows the drag as refused.
/// - **Between rows**: a page among pages, a folder among folders, in the container the row is in
///   (a folder dragged over another folder row's top or bottom quarter goes beside it; over its
///   middle, into it). An accent line marks the place (`ListRow.insertionEdge`). Placing a page
///   makes its folder's sort *Manual*, numbered first as the screen showed it, so it lands where
///   it was let go (`LibraryStore.arrange`).
/// - What doesn't drag: the home's Favorites tab and search results (`LibraryScreenKey.filtered`:
///   their rows come from across the tree, so a place beside one isn't a place in it), a page
///   played without saving (not in the Library), any row in Edit (which has its own drag
///   handles). A book's or series' chapters drag as any page.
///
/// SwiftUI's List takes no drops of its own here (neither on its rows nor between them), so the
/// surface lays one drop zone over itself while a Library row is dragged (`libraryDropZone`).
/// Rows tell the screen state where they are (`libraryDropRow`), and the zone finds the row
/// under the drag. The zone covers the whole surface, so a drag let go anywhere ends there.
/// Lists don't scroll by themselves under a drag.
///
/// The drag carries the row's id under a type of the app's own (`UTType.libraryItem`), so no text
/// field takes it.
extension UTType {
    /// A Library row dragged inside the app. Declared in Info.plist (`project.yml`).
    static let libraryItem = UTType(exportedAs: "com.jimmyyao.reader.library-item")
}

extension LibraryItemID {
    /// What the drag carries: "folder:<id>", "page:<key>".
    var payload: String {
        switch self {
        case .folder(let id): "folder:\(id.uuidString)"
        case .article(let key): "page:\(key.uuidString)"
        }
    }
}

/// Which Library screen a row is on: the home, or a pushed route. Only the screen on top takes
/// drops (`libraryDropZone`).
enum LibraryScreenKey: Hashable {
    case home
    case route(LibraryRoute)
    /// The home filtered, on its Favorites tab or by a search (`under` nil), or a folder's search
    /// (`under` its id): rows from anywhere in the tree or below the folder, each showing where it
    /// is (`place(of:)`). None lifts or takes a drop (the zone looks for `.home`), and a folder row
    /// opens under its parents (`LibraryStore.path(to:)`).
    case filtered(under: UUID?)

    var isFiltered: Bool {
        if case .filtered = self { true } else { false }
    }

    /// Where a row in `folder` is, on a filtered list: the folder's path from the top, or on a
    /// folder's search from below it ("Bonds"); nil where the row is no further down than the
    /// list's own screen (the top level, the searched folder), which shows it as that screen does.
    func place(of folder: Folder?) -> String? {
        guard case .filtered(let under) = self, let folder, folder.id != under else { return nil }
        let path = folder.ancestors.reversed() + [folder]
        let below = under.flatMap { id in path.firstIndex { $0.id == id } }.map { path.index(after: $0) } ?? path.startIndex
        return path[below...].map(\.name).joined(separator: " › ")
    }
}

/// Where the rows on screen are, for the drop zone: frames in global coordinates, kept as they
/// move (scrolling, rows coming and going) without redrawing anything.
final class LibraryDropRows {
    struct Row {
        var screen: LibraryScreenKey
        var frame: CGRect
    }

    private(set) var rows: [LibraryItemID: Row] = [:]

    func set(_ id: LibraryItemID, screen: LibraryScreenKey, frame: CGRect) {
        rows[id] = Row(screen: screen, frame: frame)
    }

    func remove(_ id: LibraryItemID, screen: LibraryScreenKey) {
        if rows[id]?.screen == screen { rows[id] = nil }
    }

    /// The row of `screen` under `point` (global coordinates), and where in its height (0…1).
    func row(at point: CGPoint, on screen: LibraryScreenKey) -> (id: LibraryItemID, fraction: CGFloat)? {
        guard let (id, row) = rows.first(where: { $0.value.screen == screen && $0.value.frame.contains(point) }),
              row.frame.height > 0 else { return nil }
        return (id, (point.y - row.frame.minY) / row.frame.height)
    }
}

extension EnvironmentValues {
    /// The Library screen the rows below are on.
    @Entry var libraryScreenKey: LibraryScreenKey = .home
}

extension View {
    /// A Library row that lifts into a drag on a long press. nil: it doesn't drag.
    func libraryDrag(_ id: LibraryItemID?, in screen: LibraryScreenState) -> some View {
        modifier(LibraryDragSource(id: id, screen: screen))
    }

    /// A row the drop zone can find: a folder to drop on, a row to drop beside.
    func libraryDropRow(_ id: LibraryItemID, in screen: LibraryScreenState) -> some View {
        modifier(LibraryDropRowFrame(id: id, screen: screen))
    }

    /// The surface's drop zone (`LibraryDrag`), over everything while a Library row is dragged;
    /// `top`: the screen on top, whose rows take the drop. With the screen's haptics: a success
    /// tick when a row lands, an error buzz when a drop is refused (entering a folder that takes
    /// the row, or a new place between rows, ticks from `ListRow`).
    func libraryDropZone(_ screen: LibraryScreenState, top: LibraryScreenKey, actions: LibraryActions) -> some View {
        overlay {
            LibraryDropZoneView(zone: LibraryDropZone(screen: screen, top: top, actions: actions),
                                isActive: screen.dragging != nil)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.success, trigger: screen.landedDrops)
        .sensoryFeedback(.error, trigger: screen.refusedDrops)
    }
}

private struct LibraryDragSource: ViewModifier {
    let id: LibraryItemID?
    let screen: LibraryScreenState

    func body(content: Content) -> some View {
        if let id {
            content.onDrag {
                screen.beginDrag(id)
                return NSItemProvider(item: id.payload as NSString, typeIdentifier: UTType.libraryItem.identifier)
            }
        } else {
            content
        }
    }
}

private struct LibraryDropRowFrame: ViewModifier {
    let id: LibraryItemID
    let screen: LibraryScreenState
    @Environment(\.libraryScreenKey) private var key

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                screen.dropRows.set(id, screen: key, frame: frame)
            }
            .onDisappear { screen.dropRows.remove(id, screen: key) }
    }
}

/// What a drag over a row would do.
enum LibraryDropAim: Equatable {
    /// File it in this folder.
    case into(UUID)
    /// This folder doesn't take it (the folder itself, or one inside it).
    case refusedInto(UUID)
    /// Place it beside this row.
    case beside(LibraryItemID, VerticalEdge)
    case nothing

    /// Over a row `fraction` of the way down (0 top, 1 bottom): a page dragged over a folder
    /// goes into it; a folder over a folder goes beside it from the top or bottom quarter, else
    /// into it; a row over a row of its own kind goes beside it from the half it is in; a page
    /// over a page row that isn't in the Library, or a folder over a page, does nothing.
    static func aim(dragging: LibraryItemID, over row: LibraryItemID, fraction: CGFloat,
                    takesInto: Bool, besideAllowed: Bool) -> LibraryDropAim {
        switch (dragging, row) {
        case (.article, .folder(let id)):
            return takesInto ? .into(id) : .refusedInto(id)
        case (.folder, .folder(let id)):
            if besideAllowed, fraction < 0.25 { return .beside(row, .top) }
            if besideAllowed, fraction > 0.75 { return .beside(row, .bottom) }
            return takesInto ? .into(id) : .refusedInto(id)
        case (.article, .article):
            guard besideAllowed else { return .nothing }
            return .beside(row, fraction < 0.5 ? .top : .bottom)
        case (.folder, .article):
            return .nothing
        }
    }
}

/// The drop zone: finds the row under the drag on the screen on top, shows what letting go there
/// would do, and does it.
@MainActor
struct LibraryDropZone {
    let screen: LibraryScreenState
    let top: LibraryScreenKey
    let actions: LibraryActions

    /// The drag moved to `point` (global coordinates): what letting go there would do, shown.
    func update(at point: CGPoint) -> UIDropOperation {
        let aim = aim(at: point)
        screen.show(aim)
        switch aim {
        case .into, .beside: return .move
        case .refusedInto: return .forbidden
        case .nothing: return .cancel
        }
    }

    /// Let go at `point`.
    func perform(at point: CGPoint) {
        guard let id = screen.dragging else { return }
        let landed: Bool?
        switch aim(at: point) {
        case .into(let folderID):
            landed = withAnimation(Motion.standard) { actions.file(id, into: folderID) }
        case .beside(let row, let edge):
            landed = withAnimation(Motion.standard) { actions.place(id, beside: row, edge: edge) }
        case .refusedInto:
            landed = false
        case .nothing:
            landed = nil
        }
        screen.endDrop(landed: landed)
    }

    /// Nothing to show: the drag left the zone.
    func clear() {
        screen.show(.nothing)
    }

    /// The drag ended, wherever it was let go.
    func end() {
        screen.endDrop(landed: nil)
    }

    private func aim(at point: CGPoint) -> LibraryDropAim {
        guard let dragging = screen.dragging, let (row, fraction) = screen.dropRows.row(at: point, on: top),
              row != dragging else { return .nothing }
        return LibraryDropAim.aim(dragging: dragging, over: row, fraction: fraction,
                                  takesInto: actions.canFile(dragging, into: row),
                                  besideAllowed: actions.canPlace(dragging, beside: row))
    }
}

/// The zone itself, a UIKit view: SwiftUI's drop modifiers get nothing over a List (the
/// collection view under them takes the drag), but a view with its own `UIDropInteraction` laid
/// over the List does. It takes the drag's hit tests (`UIDragEvent`s) only while a Library row is
/// dragged, and never a touch, so taps, scrolls and VoiceOver always go to the screen under it.
///
/// A row lifts (`beginDrag`) as its long press opens its menu; let go there without moving, the
/// menu stays and no drag ever starts, so nothing ends it. The next touch ends it instead: a
/// touch while a row is lifted but no drag has reached the zone means that lift is over.
private struct LibraryDropZoneView: UIViewRepresentable {
    let zone: LibraryDropZone
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(zone: zone) }

    func makeUIView(context: Context) -> ZoneView {
        let view = ZoneView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: ZoneView, context: Context) {
        view.isActive = isActive
        context.coordinator.zone = zone
    }

    final class ZoneView: UIView {
        var isActive = false
        weak var coordinator: Coordinator?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard isActive else { return nil }
            if event?.type == .touches {
                if coordinator?.hasSession == false {
                    // Not during this hit test: ending the lift redraws the surface.
                    Task { @MainActor [coordinator] in coordinator?.endStaleLift() }
                }
                return nil
            }
            return super.hitTest(point, with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var zone: LibraryDropZone
        /// A drag has reached the zone and hasn't ended.
        private(set) var hasSession = false

        init(zone: LibraryDropZone) { self.zone = zone }

        /// A row lifted, but its long press left the menu open instead of dragging.
        func endStaleLift() {
            guard !hasSession else { return }
            zone.end()
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [UTType.libraryItem.identifier]) && zone.screen.dragging != nil
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            hasSession = true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: zone.update(at: point(of: session, in: interaction)))
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            zone.clear()
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            zone.perform(at: point(of: session, in: interaction))
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            hasSession = false
            zone.end()
        }

        /// In window coordinates, SwiftUI's global space, where the rows' frames are.
        private func point(of session: UIDropSession, in interaction: UIDropInteraction) -> CGPoint {
            guard let view = interaction.view else { return .zero }
            return view.convert(session.location(in: view), to: nil)
        }
    }
}

/// Where a row let go beside another goes among its siblings. Pure, so it is tested without a
/// screen.
enum LibraryDropSlot {
    enum Placement<Item: AnyObject> {
        /// Let go where it already is: nothing changes.
        case unchanged
        /// Just before `before` among the siblings; nil: at their end.
        case before(Item?)
    }

    /// `dragged` let go on the `edge` of `row`, among `siblings` in the order on screen (`row` is
    /// one of them; `dragged` may come from elsewhere).
    static func placement<Item: AnyObject>(of dragged: Item, beside row: Item, edge: VerticalEdge,
                                           siblings: [Item]) -> Placement<Item> {
        func after(_ item: Item) -> Item? {
            guard let index = siblings.firstIndex(where: { $0 === item }), index + 1 < siblings.count else { return nil }
            return siblings[index + 1]
        }
        let before = edge == .top ? row : after(row)
        if before === dragged { return .unchanged }
        if siblings.contains(where: { $0 === dragged }), after(dragged) === before { return .unchanged }
        return .before(before)
    }
}
