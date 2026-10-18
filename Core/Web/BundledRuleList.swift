import CryptoKit
import Foundation
import WebKit

/// Block Ads' rules: a small list bundled with the app (`BlockAds.json`, WebKit's content-blocker
/// format) blocking requests to common ad and tracker hosts. Compiled once: kept in `store` under an
/// identifier that carries a hash of the JSON, so a launch looks it up, an edited list compiles anew
/// and the lists compiled from older JSON are removed.
struct BundledRuleList: ContentRuleListProvider {
    let store: WKContentRuleListStore

    private static let identifierPrefix = "BlockAds-"

    func ruleLists() async throws -> [WKContentRuleList] {
        guard let url = Bundle.main.url(forResource: "BlockAds", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let json = try String(contentsOf: url, encoding: .utf8)
        let digest = SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let identifier = Self.identifierPrefix + digest
        if let list = try? await store.contentRuleList(forIdentifier: identifier) { return [list] }
        guard let list = try await store.compileContentRuleList(forIdentifier: identifier,
                                                                encodedContentRuleList: json) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let stale = (await store.availableIdentifiers() ?? [])
            .filter { $0.hasPrefix(Self.identifierPrefix) && $0 != identifier }
        for old in stale { try? await store.removeContentRuleList(forIdentifier: old) }
        return [list]
    }
}
