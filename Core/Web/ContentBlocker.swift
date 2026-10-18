import CryptoKit
import Foundation
import Observation
import WebKit
import os

/// Block Ads (Settings › Browsing): a small built-in list (`BlockAds.json`, WebKit's content-blocker
/// format) that blocks requests to common ad and tracker hosts in every web view the app makes
/// (`WKWebViewConfiguration.appWebView`). On by default; UserDefaults `browse.blockAds`.
///
/// - **Compiled once.** The compiled list is kept in WebKit's rule-list store under an identifier
///   that carries a hash of the JSON: a launch looks it up, an edited list compiles anew and the
///   older compiled ones are removed.
/// - **Live views follow the switch.** Each web view's content controller is registered as its
///   configuration is made. The list goes on every registered controller once it is ready and when
///   the switch turns on, and comes off when it turns off. WebKit applies a controller's rule lists
///   to loads that start after the change, so a page already shown keeps its ads (or its gaps)
///   until it loads again. A view made before the list is ready (the first launch's compile, or a
///   lookup still running) gets it the same way, on its next load.
@MainActor
@Observable
final class ContentBlocker {
    static let enabledKey = "browse.blockAds"
    static let shared = ContentBlocker(defaults: .standard)

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            applyToControllers()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ruleList: WKContentRuleList?
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private var prepared = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey)
    }

    /// Puts the list on `controller` (when on and ready) and keeps it in step with the switch.
    func register(_ controller: WKUserContentController) {
        controllers.add(controller)
        if isEnabled, let ruleList { controller.add(ruleList) }
    }

    /// Looks up (or compiles) the list in WebKit's default store and applies it to the views made
    /// so far. Once per process, at launch.
    func prepare() {
        guard !prepared else { return }
        prepared = true
        Task {
            do {
                ruleList = try await Self.compiledList(in: .default())
                applyToControllers()
            } catch {
                Self.log.error("Block Ads list unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyToControllers() {
        guard let ruleList else { return }
        for controller in controllers.allObjects {
            // Removed first: adding a list a controller already holds is not documented as a no-op.
            controller.remove(ruleList)
            if isEnabled { controller.add(ruleList) }
        }
    }

    // MARK: - The list

    private static let log = Logger(subsystem: "com.jimmyyao.Reader", category: "ContentBlocker")
    private static let identifierPrefix = "BlockAds-"

    /// The bundled list's JSON.
    static func bundledJSON() throws -> String {
        guard let url = Bundle.main.url(forResource: "BlockAds", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The bundled list from `store`: looked up when this JSON was compiled before, else compiled,
    /// and the lists compiled from older JSON removed.
    static func compiledList(in store: WKContentRuleListStore) async throws -> WKContentRuleList {
        let json = try bundledJSON()
        let digest = SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let identifier = identifierPrefix + digest
        if let list = try? await store.contentRuleList(forIdentifier: identifier) { return list }
        guard let list = try await store.compileContentRuleList(forIdentifier: identifier,
                                                                encodedContentRuleList: json) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let stale = (await store.availableIdentifiers() ?? [])
            .filter { $0.hasPrefix(identifierPrefix) && $0 != identifier }
        for old in stale { try? await store.removeContentRuleList(forIdentifier: old) }
        return list
    }
}
