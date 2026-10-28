import WidgetKit
import SwiftUI
import AppIntents
import AppKit

@main
struct AthletiQWidgets: WidgetBundle {
    var body: some Widget { TeamWidget() }
}

struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AthletiQTeam", intent: SelectTeamIntent.self, provider: TeamProvider()) { entry in
            TeamWidgetView(entry: entry)
        }
        .configurationDisplayName("Team")
        .description("Live score, fixtures, results and the table for any team. Right-click › Edit to pick your team.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Configuration

struct LeagueEntity: AppEntity {
    let id: String
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "League"
    static var defaultQuery = LeagueQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ l: LeagueRef) { id = l.path; name = l.name }
}

struct LeagueQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LeagueEntity] {
        identifiers.compactMap(Catalog.league).map(LeagueEntity.init)
    }
    func suggestedEntities() async throws -> [LeagueEntity] {
        Catalog.leagues.filter { $0.kind == .team }.map(LeagueEntity.init)
    }
    func defaultResult() async -> LeagueEntity? { Catalog.league("soccer/eng.1").map(LeagueEntity.init) }
}

struct TeamEntity: AppEntity {
    let id: String   // "leaguePath|teamID"
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static var defaultQuery = TeamQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    var key: TeamKey? {
        let parts = id.split(separator: "|")
        guard parts.count == 2 else { return nil }
        return TeamKey(leaguePath: String(parts[0]), id: String(parts[1]))
    }
}

struct TeamQuery: EntityStringQuery {
    @IntentParameterDependency<SelectTeamIntent>(\.$league) var config

    private func teams(_ path: String) async -> [TeamEntity] {
        guard let l = Catalog.league(path) else { return [] }
        return await ESPN.teams(l).map { TeamEntity(id: "\(path)|\($0.id)", name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [TeamEntity] {
        var out: [TeamEntity] = []
        for id in identifiers {
            let path = String(id.split(separator: "|").first ?? "")
            if let match = await teams(path).first(where: { $0.id == id }) { out.append(match) }
        }
        return out
    }

    func suggestedEntities() async throws -> [TeamEntity] {
        await teams(config?.league.id ?? "soccer/eng.1")
    }

    func entities(matching string: String) async throws -> [TeamEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

struct SelectTeamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Team"
    static var description = IntentDescription("Pick the league and team this widget follows.")

    @Parameter(title: "League")
    var league: LeagueEntity?

    @Parameter(title: "Team")
    var team: TeamEntity?

    var teamKey: TeamKey { team?.key ?? TeamKey(leaguePath: "soccer/eng.1", id: "359") }
}

// MARK: - Timeline

struct TeamEntry: TimelineEntry {
    let date: Date
    let key: TeamKey
    let feed: TeamFeed?
    let logos: [URL: CGImage]
    var isPlaceholder = false
    var isStale = false
}

struct TeamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamEntry {
        let key = TeamKey(leaguePath: "soccer/eng.1", id: "359")
        return WidgetCache.load(key) ?? TeamEntry(date: Date(), key: key, feed: nil, logos: [:], isPlaceholder: true)
    }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> TeamEntry {
        await bestEntry(configuration.teamKey) ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<TeamEntry> {
        let now = Date()
        let key = configuration.teamKey
        let entry = await bestEntry(key) ?? TeamEntry(date: now, key: key, feed: nil, logos: [:])
        let next: Date
        if entry.feed == nil || entry.isStale {
            next = now.addingTimeInterval(2 * 60)
        } else if entry.feed?.live != nil {
            next = now.addingTimeInterval(60)
        } else if let k = entry.feed?.upcoming.first?.date, k > now {
            next = min(now.addingTimeInterval(30 * 60), k.addingTimeInterval(30))
        } else if entry.feed?.upcoming.first != nil {
            next = now.addingTimeInterval(2 * 60)
        } else {
            next = now.addingTimeInterval(30 * 60)
        }
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func bestEntry(_ key: TeamKey) async -> TeamEntry? {
        for attempt in 0..<3 {
            if let fresh = await makeEntry(key) {
                WidgetCache.save(fresh)
                return fresh
            }
            if attempt < 2 { try? await Task.sleep(for: .seconds(5)) }
        }
        return WidgetCache.load(key).map { $0.markedStale() }
    }

    private func makeEntry(_ key: TeamKey) async -> TeamEntry? {
        guard let feed = await TeamFeed.load(key) else { return nil }
        var urls: Set<URL> = []
        func add(_ t: TeamInfo?) {
            if let d = t?.darkLogo { urls.insert(d) }
            if let l = t?.logo { urls.insert(l) }
        }
        add(feed.info)
        for g in [feed.live].compactMap({ $0 }) + feed.upcoming.prefix(2) + feed.results.prefix(2) { add(g.home.team); add(g.away.team) }
        feed.table?.window(around: key.id, count: 5).forEach { add($0.team) }
        let cached = WidgetCache.load(key)?.logos ?? [:]
        let logos = await withTaskGroup(of: (URL, CGImage?).self) { group in
            for u in urls {
                if let c = cached[u] { group.addTask { (u, c) }; continue }
                group.addTask { (u, await Thumb.download(u, maxPixel: 96)) }
            }
            var out: [URL: CGImage] = [:]
            for await (u, img) in group { if let img { out[u] = img } }
            return out
        }
        return TeamEntry(date: Date(), key: key, feed: feed, logos: logos)
    }
}

extension TeamEntry {
    func markedStale() -> TeamEntry {
        guard var f = feed else { return self }
        let cutoff = Date().addingTimeInterval(-2.5 * 3600)
        f.upcoming = f.upcoming.filter { $0.date > cutoff }
        if let live = f.live, live.date < cutoff { f.live = nil }
        return TeamEntry(date: Date(), key: key, feed: f, logos: logos, isStale: true)
    }
}

/// Last good data per team on disk, so a failed refresh never blanks the widget.
enum WidgetCache {
    private struct Stored: Codable {
        let feed: TeamFeed
        let logos: [String: Data]
    }

    private static func url(_ key: TeamKey) -> URL {
        let name = "\(key.leaguePath)-\(key.id)".replacingOccurrences(of: "/", with: "_")
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("team-\(name).json")
    }

    static func save(_ entry: TeamEntry) {
        guard let feed = entry.feed else { return }
        var logos: [String: Data] = [:]
        for (u, img) in entry.logos {
            if let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) { logos[u.absoluteString] = png }
        }
        if let data = try? JSONEncoder().encode(Stored(feed: feed, logos: logos)) {
            try? data.write(to: url(entry.key), options: .atomic)
        }
    }

    static func load(_ key: TeamKey) -> TeamEntry? {
        guard let data = try? Data(contentsOf: url(key)),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        var logos: [URL: CGImage] = [:]
        for (k, png) in s.logos { if let u = URL(string: k), let img = Thumb.cgImage(png, maxPixel: 96) { logos[u] = img } }
        return TeamEntry(date: s.feed.updated, key: key, feed: s.feed, logos: logos)
    }
}
