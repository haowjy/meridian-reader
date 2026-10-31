import SwiftUI

/// A site on the start page's Frequently Visited: its home page, its name and its icon.
struct FrequentSite: Equatable, Identifiable {
    /// The host without "www.", lowercased: one tile per site.
    let id: String
    let name: String
    let url: URL
    var icon: Data?
}

/// The start page's Frequently Visited, from the browser's History alone (no tracking of its own).
/// History keeps one visit per page, the last `RecentVisit.maxEntries`, so a site's count is how
/// many of its pages are there: the most first, then the most recently visited. While fewer
/// sites than one row (`rowLength`) have been visited, starter sites fill the row.
enum FrequentlyVisited {
    static let rowLength = 4
    /// Two rows; *Show All* opens History.
    static let limit = 8

    /// Shown until visits fill the first row.
    static let starters = [
        starter("Wikipedia", "https://en.wikipedia.org/"),
        starter("Standard Ebooks", "https://standardebooks.org/"),
        starter("Project Gutenberg", "https://www.gutenberg.org/"),
    ]

    static func sites(from visits: [RecentVisit]) -> [FrequentSite] {
        let bySite = Dictionary(grouping: visits.filter { $0.url?.isWeb == true && !$0.host.isEmpty }) { siteID($0.host) }
        var sites = bySite.values
            .map { visits in (visits: visits, latest: visits.map(\.visitedAt).max() ?? .distantPast) }
            .sorted { ($0.visits.count, $0.latest) > ($1.visits.count, $1.latest) }
            .prefix(limit)
            .compactMap { site(from: $0.visits) }
        for starter in starters where sites.count < rowLength && !sites.contains(where: { $0.id == starter.id }) {
            sites.append(starter)
        }
        return sites
    }

    /// The site's home page on the scheme and host it was last visited on, with the newest visit's
    /// icon that fills a tile.
    private static func site(from visits: [RecentVisit]) -> FrequentSite? {
        let newest = visits.sorted { $0.visitedAt > $1.visitedAt }
        guard let latest = newest.first, let scheme = latest.url?.scheme,
              let url = URL(string: "\(scheme)://\(latest.host)/") else { return nil }
        let id = siteID(latest.host)
        let icon = newest.lazy.compactMap(\.faviconData).first(where: FaviconFetcher.isTileSized)
        return FrequentSite(id: id, name: id, url: url, icon: icon)
    }

    private static func siteID(_ host: String) -> String {
        let host = host.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func starter(_ name: String, _ address: String) -> FrequentSite {
        let url = URL(string: address)!
        return FrequentSite(id: siteID(url.host ?? address), name: name, url: url)
    }
}

/// Frequently Visited as Safari draws it: a grid of icon tiles, four to a row, each opening its
/// site in the browser. At the accessibility sizes four names can't share a row without breaking
/// their words, so each site takes a row of its own: its tile, then its name beside it.
struct FrequentlyVisitedGrid: View {
    let sites: [FrequentSite]
    var onOpen: (FrequentSite) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(sites) { tile($0) }
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs, alignment: .top),
                                     count: FrequentlyVisited.rowLength),
                      spacing: Spacing.m) {
                ForEach(sites) { tile($0) }
            }
        }
    }

    private func tile(_ site: FrequentSite) -> some View {
        let inRow = typeSize.isAccessibilitySize
        let layout = inRow ? AnyLayout(HStackLayout(spacing: Spacing.s))
            : AnyLayout(VStackLayout(spacing: Spacing.xs))
        return Button { onOpen(site) } label: {
            layout {
                ArtworkTile(image: site.icon.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                            letter: site.name, size: Glyph.siteTile)
                // A host breaks after a dot ("news." / "example.com"), never mid-word.
                Text(site.name.replacingOccurrences(of: ".", with: ".\u{200B}"))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(inRow ? nil : 2)
                    .multilineTextAlignment(inRow ? .leading : .center)
                    .frame(maxWidth: .infinity, alignment: inRow ? .leading : .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(site.name)
        .accessibilityHint(String(localized: "Opens in Browse"))
        .accessibilityIdentifier("frequentSiteTile")
    }
}
