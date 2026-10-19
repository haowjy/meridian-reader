import SwiftUI

/// Every empty list says so the same way: the system's empty view (`ContentUnavailableView`),
/// its symbol from `Icons`, a Title Case title ("No History Yet"), a sentence-case line under it,
/// and, where the list has a way to fill it, its actions (an `ActionButtonRow`). The Library's
/// Everything, Favorites and Recent, the browser's History, Downloads and a folder that is gone.
struct EmptyState<Actions: View>: View {
    let title: String
    let symbol: String
    var description: Text?
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, symbol: String, description: Text?, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.symbol = symbol
        self.description = description
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            description
        } actions: {
            actions()
        }
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: String, symbol: String, description: String? = nil) {
        self.init(title, symbol: symbol, description: description.map { Text($0) }) { EmptyView() }
    }

    /// A description with a symbol in it (`Text.symbol`).
    init(_ title: String, symbol: String, description: Text) {
        self.init(title, symbol: symbol, description: Optional(description)) { EmptyView() }
    }
}

#if DEBUG
struct EmptyStateGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("no actions") {
                EmptyState("No History Yet", symbol: Icons.history, description: "Pages you open show up here.")
            }
            PreviewState("with actions") {
                EmptyState("Find Something to Listen To", symbol: Icons.library,
                           description: Text("Pages you save show up here.")) {
                    ActionButtonRow { fit in
                        PillButton("Browse the Web", shortTitle: "Browse", systemImage: Icons.browser, style: .filled,
                                   fit: fit) {}
                        PillButton("Import a Book", shortTitle: "Import", systemImage: Icons.book, style: .neutral,
                                   fit: fit) {}
                    }
                }
            }
        }
    }
}

#Preview("EmptyState · light", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.light) }
#Preview("EmptyState · dark", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.dark) }
#Preview("EmptyState · AX5", traits: .sizeThatFitsLayout) { EmptyStateGallery().previewVariant(.largestText) }
#endif
