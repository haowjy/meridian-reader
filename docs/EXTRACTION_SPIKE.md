# Extraction spike — Mozilla Readability (live DOM snapshot)

## Approach
1. Browse keeps a live `WKWebView` in `WebViewStore`.
2. On Reader/Save, snapshot `document.documentElement.outerHTML`.
3. `ReadabilityArticleExtractor` loads that HTML into an **off-screen** `WKWebView` with the page URL as baseURL, injects bundled `Readability.js` (+ readerable helper), and calls `new Readability(document.cloneNode(true)).parse()`.
4. Features still only see `ArticleExtracting` — engine remains swappable.

## Why snapshot + off-screen (not inject into the visible WebView)
- Avoids mutating the user’s live page / CSP fights with injected scripts on some sites.
- Still uses a real DOM (not fetch-only), so JS-rendered content already in the live WebView is included in the snapshot.

## Manual test matrix
| URL type | Example | Expect |
|----------|---------|--------|
| News article | https://www.bbc.com/news | Clean title + body |
| Longform / blog | any Medium-style or blog post | Clean body |
| Homepage | https://example.com or news home | Fail with clear reason, **nothing saved** |
| Fake fail toggle | any | Fail path / no save |

## Swap notes
Replace `ReadabilityArticleExtractor` in `ReaderApp` without touching Saved/Speech. Keep `FakeArticleExtractor` for UI failure demos.
