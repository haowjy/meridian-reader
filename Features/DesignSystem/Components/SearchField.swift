import SwiftUI

/// The Library's search capsule: 🔍, the text, and ⓧ to clear once there is text. The same field
/// capsule as the address field.
///
/// ```
/// ( 🔍 Search Library                   ⓧ )
/// ```
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search Library"
    /// Ties the field to the caller's focus (the search session); nil: the field keeps its own.
    var focus: FocusState<Bool>.Binding?
    /// The text field's accessibility identifier.
    var fieldIdentifier = "searchField"
    var onSubmit: () -> Void = {}

    @Environment(\.isChromeField) private var isChromeField

    var body: some View {
        let clearable = !text.isEmpty
        HStack(spacing: Spacing.xs) {
            Image(systemName: Icons.search)
                .font(isChromeField ? BottomChrome.chromeGlyph : .caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: Glyph.fieldLeading, height: Glyph.fieldLeading)
                .accessibilityHidden(true)

            textField
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(fieldIdentifier)

            if clearable {
                Button {
                    text = ""
                } label: {
                    Image(systemName: Icons.clearText)
                        .foregroundStyle(Palette.secondaryInk)
                        .fieldControlFrame()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        // In the chrome 🔍 and ⊗ are 30 pt slots concentric with the end caps (`fieldEndInset`).
        .bottomChromeField(leading: isChromeField ? BottomChrome.fieldEndInset : Spacing.s,
                           trailing: clearable ? (isChromeField ? BottomChrome.fieldEndInset : Spacing.xxs) : Spacing.s)
    }

    @ViewBuilder
    private var textField: some View {
        let field = TextField(prompt, text: $text)
        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}

#if DEBUG
struct SearchFieldGallery: View {
    @State private var empty = ""
    @State private var typed = "tides"

    var body: some View {
        PreviewGallery {
            PreviewState("empty") { SearchField(text: $empty) }
            PreviewState("with text") { SearchField(text: $typed) }
        }
    }
}

#Preview("SearchField · light", traits: .sizeThatFitsLayout) { SearchFieldGallery().previewVariant(.light) }
#Preview("SearchField · dark", traits: .sizeThatFitsLayout) { SearchFieldGallery().previewVariant(.dark) }
#Preview("SearchField · AX5", traits: .sizeThatFitsLayout) { SearchFieldGallery().previewVariant(.largestText) }
#endif
