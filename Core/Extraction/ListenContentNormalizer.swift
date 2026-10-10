import Foundation
import WebKit

/// Makes every piece of readable text sit inside a listen block (`ListenHTMLBlocks`), so speech,
/// tap and highlight never skip it: loose text in a `<div>`, lines between `<br><br>`, the lead-in
/// of a list item or quote that also holds blocks (`ReaderNormalize.js`). Runs in an off-screen
/// web view (`OffscreenWebView`).
///
/// - **Web pages** run it after Readability, in the web view Readability read the page in: the
///   document the two shared when they ran as one script, so the output is unchanged
///   (`ListenContentGoldenTests`).
/// - **Book chapters** run it without Readability, one at a time in one reused web view holding a
///   blank standards-mode page, after pictures, embedded media, footnote asides, note references
///   and back-links are taken out and links unwrapped (`ReaderBookChapter.js`). A book's endnotes
///   stay, on their own back-matter page.
@MainActor
final class ListenContentNormalizer {
    private var bookView: WKWebView?

    /// Web pages: Readability's article HTML, normalized in `webView`, where Readability ran.
    static func normalize(_ html: String, in webView: WKWebView) async throws -> String {
        try await install(["ReaderNormalize"], in: webView)
        return try await run("return __readerNormalizeContent(html, selector);", html: html, in: webView)
    }

    /// A book chapter's body-level XHTML, normalized.
    func normalizeBookChapter(_ xhtml: String) async throws -> String {
        let view = try await bookWebView()
        return try await Self.run("return __readerNormalizeContent(__readerPrepareBookChapter(html), selector);",
                                  html: xhtml, in: view)
    }

    private func bookWebView() async throws -> WKWebView {
        if let bookView { return bookView }
        let view = OffscreenWebView.make()
        try await OffscreenWebView.load(view, html: "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body></body></html>",
                                        baseURL: nil)
        try await Self.install(["ReaderNormalize", "ReaderBookChapter"], in: view)
        bookView = view
        return view
    }

    private static func install(_ scripts: [String], in webView: WKWebView) async throws {
        for name in scripts {
            guard let source = ReaderScripts.source(name) else {
                throw ExtractionError.engineFailed(message: "Missing \(name).js in app bundle. Check Resources/Readability.")
            }
            _ = try await webView.evaluateJavaScript(source)
        }
    }

    /// `body` with `html` and the listen-block selector as its arguments, in the page's world,
    /// where the installed scripts live.
    private static func run(_ body: String, html: String, in webView: WKWebView) async throws -> String {
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(body, arguments: ["html": html, "selector": ListenHTMLBlocks.innerSelector],
                                                           in: nil, contentWorld: .page)
        } catch {
            throw ExtractionError.engineFailed(message: "Couldn't prepare the text for listening: \(error.localizedDescription)")
        }
        guard let normalized = result as? String else {
            throw ExtractionError.engineFailed(message: "Couldn't prepare the text for listening.")
        }
        return normalized
    }
}
