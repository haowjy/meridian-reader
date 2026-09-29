import CryptoKit
import Foundation

/// Stable listen/bake identity shared by Browse Reader and Saved.
///
/// v2 (see docs/ARTICLE_IDENTITY.md):
/// - **Key = canonical URL.** One article per canonical URL; the same chapter reopened from
///   Browse, Saved, or after an app restart resolves to the same cache key / `SpeechSession.id`.
///   A saved article's `id` *is* that key for new saves; legacy saves (random UUIDs) are found
///   by `SavedArticle.canonicalURL` and keep their id.
/// - **Content fingerprint only detects change** (listen-block text after anti-copy stripping,
///   never raw HTML). Per-paragraph text hashes in the TTS cache let a changed page reuse audio
///   for unchanged paragraphs and re-bake only what changed.
enum ArticleIdentity {
    /// Namespace for URL-derived article keys (v2).
    private static let urlKeyNamespace = "com.jimmyyao.Reader.article.v2"
    /// v1 namespace (URL + raw content fingerprint). Only used to adopt old ephemeral caches.
    private static let legacyKeyNamespace = "com.jimmyyao.Reader.tts.v1"

    /// Query parameters that never change article content.
    private static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid",
        "mc_cid", "mc_eid", "igshid", "si", "ref_src", "ref_url", "_hsenc", "_hsmi",
        "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id",
    ]

    // MARK: - Canonical URL

    /// Lowercased scheme + host, no fragment, tracking params (`utm_*`, `fbclid`, …) removed,
    /// trailing slash trimmed (non-root). Remaining query items keep their order.
    static func canonicalURLString(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if let items = components.queryItems {
            let kept = items.filter { !isTrackingParam($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        var path = components.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
            components.percentEncodedPath = path
        }
        return components.string ?? url.absoluteString
    }

    static func canonicalURLString(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return canonicalURLString(from: url)
    }

    private static func isTrackingParam(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || trackingParams.contains(lower)
    }

    // MARK: - Keys

    /// Deterministic article key for a canonical URL. Same URL → same UUID forever.
    static func articleKey(canonicalURL: String) -> UUID {
        uuid(from: [Data(urlKeyNamespace.utf8), Data(canonicalURL.utf8)])
    }

    static func articleKey(url: URL) -> UUID {
        articleKey(canonicalURL: canonicalURLString(from: url))
    }

    /// v1 key (URL with query + SHA(plainText, cleanedHTML)). Content-sensitive, so any dynamic
    /// markup produced a new key → full re-bake. Kept only so old ephemeral caches can be adopted.
    static func legacyEphemeralCacheKey(url: URL, plainText: String, cleanedHTML: String) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data(plainText.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(cleanedHTML.utf8))
        let fingerprint = Data(hasher.finalize())
        return uuid(from: [
            Data(legacyKeyNamespace.utf8),
            Data(legacyCanonicalURLString(from: url).utf8),
            fingerprint,
        ])
    }

    /// v1 canonical form (kept query/tracking params).
    private static func legacyCanonicalURLString(from url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if let host = components?.host {
            components?.host = host.lowercased()
        }
        if var path = components?.path, path.count > 1, path.hasSuffix("/") {
            path.removeLast()
            components?.path = path
        }
        return components?.string ?? url.absoluteString
    }

    // MARK: - Content fingerprints

    /// Change detector over the listen paragraphs (post anti-copy / normalize), not raw HTML.
    static func contentFingerprint(paragraphs: [String]) -> String {
        var hasher = SHA256()
        for paragraph in paragraphs {
            hasher.update(data: Data(normalized(paragraph).utf8))
            hasher.update(data: Data([0x1F]))
        }
        return hex(hasher.finalize(), bytes: 16)
    }

    /// Per-paragraph text hash stored next to each CAF so audio is only reused for identical text.
    static func paragraphHash(_ text: String) -> String {
        hex(SHA256.hash(data: Data(normalized(text).utf8)), bytes: 12)
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    // MARK: - Helpers

    private static func uuid(from parts: [Data]) -> UUID {
        var hasher = SHA256()
        for (i, part) in parts.enumerated() {
            if i > 0 { hasher.update(data: Data([0])) }
            hasher.update(data: part)
        }
        let b = Array(hasher.finalize().prefix(16))
        return UUID(uuid: (
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
        ))
    }

    private static func hex<D: Sequence>(_ digest: D, bytes: Int) -> String where D.Element == UInt8 {
        digest.prefix(bytes).map { String(format: "%02x", $0) }.joined()
    }
}
