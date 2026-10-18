import Foundation
import Observation
import WebKit
import os

/// Where Block Ads' rules come from: compiled WebKit content rule lists. `ContentBlocker` asks once,
/// at launch; until the answer comes, web views load unblocked. The app's provider is chosen in
/// `AppComposition.makeContentBlocker`.
@MainActor
protocol ContentRuleListProvider {
    func ruleLists() async throws -> [WKContentRuleList]
}

/// Block Ads (Settings › Browsing): its provider's rule lists on every web view the app makes
/// (`WKWebViewConfiguration.appWebView`). On by default; UserDefaults `browse.blockAds`.
///
/// Live views follow the switch. Each web view's content controller is registered as its
/// configuration is made. The lists go on every registered controller once they are ready and when
/// the switch turns on, and come off when it turns off. WebKit applies a controller's rule lists to
/// loads that start after the change, so a page already shown keeps its ads (or its gaps) until it
/// loads again. A view made before the lists are ready (the first launch's compile, or a lookup
/// still running) gets them the same way, on its next load.
@MainActor
@Observable
final class ContentBlocker {
    static let enabledKey = "browse.blockAds"

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            applyToControllers()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ruleLists: [WKContentRuleList] = []
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()

    private static let log = Logger(subsystem: "com.jimmyyao.Reader", category: "ContentBlocker")

    /// Starts asking `provider` for its lists; they go on the views registered by then once it answers.
    init(provider: any ContentRuleListProvider, defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey)
        Task {
            do {
                ruleLists = try await provider.ruleLists()
                applyToControllers()
            } catch {
                Self.log.error("Block Ads lists unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Puts the lists on `controller` (when on and ready) and keeps them in step with the switch.
    func register(_ controller: WKUserContentController) {
        controllers.add(controller)
        guard isEnabled else { return }
        for list in ruleLists { controller.add(list) }
    }

    private func applyToControllers() {
        for controller in controllers.allObjects {
            for list in ruleLists {
                // Removed first: adding a list a controller already holds is not documented as a no-op.
                controller.remove(list)
                if isEnabled { controller.add(list) }
            }
        }
    }
}
