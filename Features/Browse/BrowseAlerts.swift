import SwiftUI

/// The browser's two alerts: a failed extraction, and a dictation problem (permission, mic).
struct BrowseAlerts: ViewModifier {
    @Binding var extractionError: String?
    let dictation: AddressDictation?

    func body(content: Content) -> some View {
        content
            .alert("Couldn’t extract", isPresented: Binding(
                get: { extractionError != nil },
                set: { if !$0 { extractionError = nil } }
            )) {
                Button(Verbs.ok, role: .cancel) { extractionError = nil }
            } message: {
                Text(extractionError ?? "")
            }
            .alert("Dictation", isPresented: Binding(
                get: { dictation?.errorMessage != nil },
                set: { if !$0 { dictation?.errorMessage = nil } }
            )) {
                Button("Open Settings") {
                    dictation?.errorMessage = nil
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(Verbs.ok, role: .cancel) { dictation?.errorMessage = nil }
            } message: {
                Text(dictation?.errorMessage ?? "")
            }
    }
}
