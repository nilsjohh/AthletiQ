import Foundation

/// Everything the app and widget need about one team.
struct TeamFeed: Sendable, Codable {
    var key: TeamKey
    var info: TeamInfo?
    var live: Game?
    var upcoming: [Game]
    var results: [Game]
    var table: StandingsGroup?
    var tableLeaguePath: String?
    var record: String?
    var standingSummary: String?
    var venue: String?
    var updated: Date

    var position: StandingRow? { table?.rows.first { $0.team.id == key.id } }

    static func load(_ key: TeamKey, withTable: Bool = true) async -> TeamFeed? {
        guard let league = key.league else { return nil }
        async let gamesTask = ESPN.teamGames(key)
        async let detailTask = ESPN.teamDetail(key)
        var games = await gamesTask
        let detail = await detailTask
        if games.isEmpty && detail == nil { return nil }

        // Football clubs: show the domestic league table even when opened from a cup or European page.
        var tableLeague = league
        if league.isSoccer {
            var counts: [String: Int] = [:]
            for g in games {
                guard let p = g.leaguePath, let l = Catalog.league(p),
                      !["Europe", "World", "South America"].contains(l.region), !l.name.contains("Cup") else { continue }
                counts[p, default: 0] += 1
            }
            if let best = counts.max(by: { $0.value < $1.value })?.key, let l = Catalog.league(best) { tableLeague = l }
        }
        let groups: [StandingsGroup] = withTable ? await ESPN.standings(tableLeague).groups : []

        // Schedule feeds can lag at kickoff; refresh anything that should be in play.
        let now = Date()
        for (i, g) in games.enumerated() {
            let shouldBeLive = g.state == .live
                || (g.state == .pre && g.date < now && now.timeIntervalSince(g.date) < 4 * 3600)
            guard shouldBeLive, let path = g.leaguePath,
                  let fresh = await ESPN.summary(path, id: g.id)?.game else { continue }
            var merged = fresh
            merged.competition = g.competition ?? fresh.competition
            merged.venue = g.venue ?? fresh.venue
            merged.date = g.date
            games[i] = merged
        }

        let info = detail?.info ?? games.first.flatMap { $0.side(of: key.id)?.team }
        return TeamFeed(
            key: key,
            info: info,
            live: games.first { $0.state == .live },
            upcoming: games.filter { $0.state == .pre && $0.date > now.addingTimeInterval(-4 * 3600) }
                .sorted { $0.date < $1.date },
            results: games.filter { $0.state == .post && $0.completed }.sorted { $0.date > $1.date },
            table: groups.first { $0.rows.contains { $0.team.id == key.id } },
            tableLeaguePath: tableLeague.path,
            record: detail?.record,
            standingSummary: detail?.standingSummary,
            venue: detail?.venue,
            updated: now)
    }
}

enum Fmt {
    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func shortDay(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tmrw" }
        if cal.isDateInYesterday(d) { return "Yest" }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func range(_ a: Date, _ b: Date?) -> String {
        guard let b, !Calendar.current.isDate(a, inSameDayAs: b) else { return a.formatted(.dateTime.day().month(.abbreviated)) }
        return "\(a.formatted(.dateTime.day().month(.abbreviated))) – \(b.formatted(.dateTime.day().month(.abbreviated)))"
    }

    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
