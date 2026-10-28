import Foundation

/// Client for ESPN's public JSON feeds.
enum ESPN {
    static let site = "https://site.api.espn.com/apis/site/v2/sports"
    static let standingsBase = "https://site.api.espn.com/apis/v2/sports"
    static let leadersBase = "https://site.web.api.espn.com/apis/site/v3/sports"

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: c)
    }()

    static func fetch<T: Decodable>(_ type: T.Type, _ url: String) async throws -> T {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: u)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func merge(_ games: [Game]) -> [Game] {
        func rank(_ g: Game) -> Int { g.state == .post ? 2 : (g.state == .live ? 1 : 0) }
        var byID: [String: Game] = [:]
        for g in games {
            if let old = byID[g.id], rank(old) >= rank(g) { continue }
            byID[g.id] = g
        }
        return byID.values.sorted { $0.date < $1.date }
    }

    private static func keyFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = format
        return f
    }

    // MARK: Scoreboards

    static func scoreboard(_ path: String, query: String) async -> RawScoreboard? {
        try? await fetch(RawScoreboard.self, "\(site)/\(path)/scoreboard?\(query)&limit=400")
    }

    /// Recent and upcoming games for a team league.
    static func leagueGames(_ league: LeagueRef) async -> (games: [Game], logo: URL?) {
        if league.kind == .cricket { return (await cricketMatches(), nil) }
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let keys: [String]
        if league.isSoccer || league.sport == .rugby || league.sport == .lacrosse {
            let f = keyFormatter("yyyyMM")
            keys = [-1, 0, 1].compactMap { cal.date(byAdding: .month, value: $0, to: now) }.map(f.string(from:))
        } else {
            let f = keyFormatter("yyyyMMdd")
            let range = league.isCollege ? (-2...5) : (-3...7)
            keys = range.compactMap { cal.date(byAdding: .day, value: $0, to: now) }.map(f.string(from:))
        }
        let boards = await withTaskGroup(of: RawScoreboard?.self) { group in
            for k in keys { group.addTask { await scoreboard(league.path, query: "dates=\(k)") } }
            var out: [RawScoreboard] = []
            for await b in group { if let b { out.append(b) } }
            return out
        }
        let info = boards.compactMap { $0.leagues?.first }.first
        let logo = info?.logos?.first?.href.flatMap { URL(string: $0) }
        let games = boards.flatMap { b in
            (b.events ?? []).compactMap { $0.game(competition: league.name, path: league.path) }
        }
        return (merge(games), logo)
    }

    static func leagueLogo(_ league: LeagueRef) async -> URL? {
        let b = await scoreboard(league.path, query: "")
        return b?.leagues?.first?.logos?.first?.href.flatMap { URL(string: $0) }
    }

    /// Live games right now for a league (today's board).
    static func todaysGames(_ league: LeagueRef) async -> [Game] {
        if league.kind == .cricket { return await cricketMatches() }
        guard league.kind == .team, let b = await scoreboard(league.path, query: "") else { return [] }
        return (b.events ?? []).compactMap { $0.game(competition: league.name, path: league.path) }
    }

    static func cricketMatches() async -> [Game] {
        guard let panel = try? await fetch(RawScorePanel.self, "\(site)/cricket/scorepanel") else { return [] }
        return merge((panel.scores ?? []).flatMap { block in
            let name = block.leagues?.first?.name
            return (block.events ?? []).compactMap { $0.game(competition: name, path: "cricket") }
        })
    }

    // MARK: Summary

    static func summary(_ path: String, id: String) async -> GameDetail? {
        guard let raw = try? await fetch(RawSummary.self, "\(site)/\(path)/summary?event=\(id)"),
              let comp = raw.header?.competitions?.first,
              var game = comp.game(id: raw.header?.id ?? id, date: nil, fallbackStatus: nil,
                                   competition: Catalog.league(path)?.name ?? raw.header?.league?.name,
                                   path: path, seasonType: nil) else { return nil }
        if game.venue == nil { game.venue = raw.venueName }

        let homeID = game.home.team.id
        var events: [KeyEvent] = []
        let wanted = ["goal", "card", "penalty", "own goal"]
        for (i, k) in (raw.keyEvents ?? []).enumerated() {
            let t = k.type?.text ?? ""
            guard wanted.contains(where: { t.lowercased().contains($0) }) else { continue }
            events.append(KeyEvent(id: k.id ?? "\(i)", clock: k.clockValue ?? "", type: t,
                                   text: k.text ?? "", teamID: k.team?.id))
        }
        if events.isEmpty {
            for (i, k) in (raw.scoringPlays ?? []).enumerated() {
                let clock = [k.periodNumber.map { periodName(path, $0) }, k.clockValue].compactMap { $0 }.joined(separator: " ")
                events.append(KeyEvent(id: k.id ?? "\(i)", clock: clock, type: k.type?.text ?? "Score",
                                       text: k.text ?? "", teamID: k.team?.id))
            }
        }

        var stats: [StatLine] = []
        if let teams = raw.boxscore?.teams, teams.count == 2 {
            let h = teams.first { $0.team?.id == homeID } ?? teams[1]
            let a = teams.first { $0.team?.id != homeID } ?? teams[0]
            for s in h.statistics ?? [] {
                guard let key = s.name, let hv = s.displayValue,
                      let av = a.statistics?.first(where: { $0.name == key })?.displayValue else { continue }
                let label = s.label ?? prettify(key)
                if hv.isEmpty && av.isEmpty { continue }
                stats.append(StatLine(label: label, home: hv, away: av))
            }
        }

        var performers: [PerformerPair] = []
        if let ls = raw.leaders {
            let h = ls.first { $0.team?.id == homeID }
            let a = ls.first { $0.team?.id != homeID }
            for cat in h?.leaders ?? [] {
                guard let name = cat.name else { continue }
                let hl = cat.category(soccer: false)?.leaders.first
                let al = a?.leaders?.first { $0.name == name }?.category(soccer: false)?.leaders.first
                performers.append(PerformerPair(category: cat.displayName ?? prettify(name), home: hl, away: al))
            }
        }

        let periods = max(game.home.linescores.count, game.away.linescores.count)
        let labels = (0..<periods).map { periodName(path, $0 + 1) }
        return GameDetail(game: game, keyEvents: events, teamStats: Array(stats.prefix(14)),
                          performers: Array(performers.prefix(6)), periodLabels: labels)
    }

    static func periodName(_ path: String, _ n: Int) -> String {
        if path.hasPrefix("soccer") || path.hasPrefix("rugby") { return n <= 2 ? "\(n == 1 ? "1st" : "2nd")" : (n <= 4 ? "ET\(n - 2)" : "PEN") }
        if path.hasPrefix("hockey") { return n <= 3 ? "P\(n)" : (n == 4 ? "OT" : "SO") }
        if path.hasPrefix("baseball") || path.hasPrefix("cricket") { return "\(n)" }
        if path.contains("college-basketball") { return n <= 2 ? "H\(n)" : "OT\(n - 2 > 1 ? String(n - 2) : "")" }
        return n <= 4 ? "Q\(n)" : "OT\(n - 4 > 1 ? String(n - 4) : "")"
    }

    static func prettify(_ key: String) -> String {
        var out = ""
        for ch in key {
            if ch.isUppercase && !out.isEmpty { out.append(" ") }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: Standings

    static func standings(_ league: LeagueRef) async -> (groups: [StandingsGroup], season: String?) {
        guard let root = try? await fetch(RawStandingsNode.self, "\(standingsBase)/\(league.path)/standings") else { return ([], nil) }
        var groups: [StandingsGroup] = []
        func walk(_ node: RawStandingsNode) {
            if let entries = node.standings?.entries, !entries.isEmpty {
                var rows: [StandingRow] = []
                for (i, e) in entries.enumerated() {
                    guard let info = e.team?.info else { continue }
                    let k = e.keyed
                    let seed = k.values["playoffSeed"] ?? (league.isSoccer || league.sport == .rugby ? k.values["rank"] : nil) ?? k.values["rank"]
                    rows.append(StandingRow(team: info, rank: seed.map { Int($0) } ?? (i + 1), display: k.display,
                                            note: e.note?.description,
                                            noteColorHex: e.note?.color?.replacingOccurrences(of: "#", with: "")))
                }
                if rows.contains(where: { $0.rank == 0 }) { rows = rows.enumerated().map { var r = $1; r.rank = $0 + 1; return r } }
                rows.sort { $0.rank < $1.rank }
                groups.append(StandingsGroup(name: node.name ?? league.name, rows: rows))
            }
            node.children?.forEach(walk)
        }
        walk(root)
        return (groups, root.seasons?.first?.seasonYears ?? root.seasons?.first?.year.map(String.init))
    }

    static func driverStandings(_ league: LeagueRef) async -> [(String, [DriverStanding])] {
        guard let root = try? await fetch(RawStandingsNode.self, "\(standingsBase)/\(league.path)/standings") else { return [] }
        var out: [(String, [DriverStanding])] = []
        func walk(_ node: RawStandingsNode) {
            if let entries = node.standings?.entries, !entries.isEmpty {
                let rows: [DriverStanding] = entries.enumerated().compactMap { i, e in
                    let k = e.keyed
                    let pts = k.display["championshipPts"] ?? k.display["points"] ?? "–"
                    if let a = e.athlete, let n = a.displayName {
                        return DriverStanding(rank: Int(k.values["rank"] ?? Double(i + 1)), name: n, flag: a.flag?.url, logo: nil, points: pts)
                    }
                    if let t = e.team?.info {
                        return DriverStanding(rank: Int(k.values["rank"] ?? Double(i + 1)), name: t.name, flag: nil, logo: t.logo, points: pts)
                    }
                    return nil
                }.sorted { $0.rank < $1.rank }
                out.append((node.name ?? "Standings", rows))
            }
            node.children?.forEach(walk)
        }
        walk(root)
        return out
    }

    // MARK: Leaders

    static func leaders(_ league: LeagueRef, teamID: String? = nil) async -> [LeaderCategory] {
        let cats: [RawLeaderCat]
        if league.isSoccer {
            cats = (try? await fetch(RawSoccerStats.self, "\(site)/\(league.path)/statistics"))?.stats ?? []
        } else {
            let q = teamID.map { "?team=\($0)" } ?? ""
            cats = (try? await fetch(RawUSLeaders.self, "\(leadersBase)/\(league.path)/leaders\(q)"))?.leaders?.categories ?? []
        }
        var all = cats.compactMap { $0.category(soccer: league.isSoccer) }
        if let teamID, !league.isSoccer {
            all = all.map { LeaderCategory(id: $0.id, title: $0.title, leaders: $0.leaders.filter { $0.team?.id == teamID || $0.team == nil }) }
                .filter { !$0.leaders.isEmpty }
        }
        let wanted = preferredLeaderCategories(league)
        if wanted.isEmpty { return all }
        let picked = wanted.compactMap { w in all.first { $0.id == w } }
        return picked.isEmpty ? Array(all.prefix(8)) : picked
    }

    static func preferredLeaderCategories(_ league: LeagueRef) -> [String] {
        switch league.sport {
        case .basketball: ["pointsPerGame", "reboundsPerGame", "assistsPerGame", "stealsPerGame", "blocksPerGame",
                           "fieldGoalPercentage", "3PointsMadePerGame", "doubleDouble"]
        case .hockey: ["points", "goals", "assists", "plusMinus", "wins", "savePct", "avgGoalsAgainst", "shutouts"]
        case .americanFootball: ["passingYards", "rushingYards", "receivingYards", "passingTouchdowns",
                                 "rushingTouchdowns", "receivingTouchdowns", "sacks", "interceptions", "totalTackles"]
        case .baseball: ["avg", "homeRuns", "RBIs", "hits", "stolenBases", "ERA", "wins", "strikeouts", "saves"]
        default: []
        }
    }

    // MARK: Teams

    static func teams(_ league: LeagueRef) async -> [TeamInfo] {
        let list = try? await fetch(RawTeamsList.self, "\(site)/\(league.path)/teams?limit=1000")
        return (list?.sports?.first?.leagues?.first?.teams ?? []).compactMap { $0.team?.info }
            .sorted { $0.name < $1.name }
    }

    static func teamDetail(_ key: TeamKey) async -> TeamDetail? {
        guard let raw = try? await fetch(RawTeamDetail.self, "\(site)/\(key.leaguePath)/teams/\(key.id)"),
              let info = raw.team?.info else { return nil }
        return TeamDetail(info: info, record: raw.record, standingSummary: raw.standingSummary,
                          venue: raw.venue, location: raw.team?.location)
    }

    static func schedule(_ key: TeamKey, fixtures: Bool) async -> [Game] {
        let league = key.league
        let base = (league?.isSoccer ?? false) ? "soccer/all" : key.leaguePath
        let url = "\(site)/\(base)/teams/\(key.id)/schedule" + (fixtures ? "?fixture=true" : "")
        guard let raw = try? await fetch(RawSchedule.self, url) else { return [] }
        return (raw.events ?? []).compactMap { e in
            let path = (league?.isSoccer ?? false) ? (e.league?.slug.map { "soccer/\($0)" } ?? key.leaguePath) : key.leaguePath
            return e.game(competition: (league?.isSoccer ?? false) ? nil : league?.name, path: path)
        }
    }

    static func teamGames(_ key: TeamKey) async -> [Game] {
        let isSoccer = key.league?.isSoccer ?? false
        if isSoccer {
            async let a = schedule(key, fixtures: true)
            async let b = schedule(key, fixtures: false)
            return merge(await a + b)
        }
        // US-style schedules: regular season plus postseason.
        async let a = schedule(key, fixtures: false)
        async let p = postseasonSchedule(key)
        return merge(await a + p)
    }

    static func postseasonSchedule(_ key: TeamKey) async -> [Game] {
        guard key.league?.hasBracket == true,
              let raw = try? await fetch(RawSchedule.self, "\(site)/\(key.leaguePath)/teams/\(key.id)/schedule?seasontype=3") else { return [] }
        return (raw.events ?? []).compactMap { $0.game(competition: key.league?.name, path: key.leaguePath) }
    }

    static func roster(_ key: TeamKey) async -> [Player] {
        guard let raw = try? await fetch(RawRoster.self, "\(site)/\(key.leaguePath)/teams/\(key.id)/roster") else { return [] }
        let flat = (raw.athletes ?? []).flatMap { $0.items ?? [$0] }
        return flat.compactMap(\.player)
    }

    // MARK: Playoffs

    static func bracket(_ league: LeagueRef) async -> Bracket? {
        guard let first = league.playoffMonths.first else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let month = cal.component(.month, from: now)
        var year = cal.component(.year, from: now)
        if month < first { year -= 1 }
        let keys = league.playoffMonths.map { String(format: "%04d%02d", year, $0) }
        let boards = await withTaskGroup(of: RawScoreboard?.self) { group in
            for k in keys { group.addTask { await scoreboard(league.path, query: "seasontype=3&dates=\(k)") } }
            var out: [RawScoreboard] = []
            for await b in group { if let b { out.append(b) } }
            return out
        }
        var games: [Game] = []
        for b in boards {
            for e in b.events ?? [] {
                guard var g = e.game(competition: league.name, path: league.path) else { continue }
                if let t = g.seasonType, t != 3 { continue }
                if g.roundName == nil, league.path == "football/nfl" {
                    switch e.week?.number {
                    case 1: g.note = "Wild Card"
                    case 2: g.note = "Divisional Round"
                    case 3: g.note = "Conference Championships"
                    case 5: g.note = "Super Bowl"
                    default: continue // Pro Bowl
                    }
                }
                games.append(g)
            }
        }
        games = merge(games)
        guard !games.isEmpty else { return nil }

        var groups: [String: [Game]] = [:]
        for g in games {
            let round = g.roundName ?? "Playoffs"
            let pair = [g.home.team.id, g.away.team.id].sorted().joined(separator: "-")
            groups["\(round)|\(pair)", default: []].append(g)
        }
        var matchups: [SeriesMatchup] = groups.map { key, gs in
            let sorted = gs.sorted { $0.date < $1.date }
            let last = sorted.last(where: { $0.state != .pre }) ?? sorted.last!
            let teams = [sorted[0].away.team, sorted[0].home.team]
            var wins = teams.map { last.seriesWins[$0.id] ?? 0 }
            if last.seriesWins.isEmpty {
                wins = teams.map { t in sorted.filter { $0.outcome(for: t.id) == .win }.count }
            }
            let summary = last.seriesSummary ?? (last.state == .post ? "Final" : Fmt.day(last.date))
            let lower = summary.lowercased()
            let decided = lower.contains("win") || lower.contains("won") || lower.contains("advance")
                || (last.seriesWins.isEmpty && last.state == .post)
            var winner: String?
            if decided { winner = wins[0] > wins[1] ? teams[0].id : (wins[1] > wins[0] ? teams[1].id : nil) }
            return SeriesMatchup(id: key, round: String(key.split(separator: "|")[0]), teams: teams, wins: wins,
                                 summary: summary, games: sorted.filter { !($0.state == .pre && $0.note?.contains("If Necessary") == true) || $0 == sorted.first },
                                 completed: decided, winnerID: winner, start: sorted[0].date)
        }
        matchups = matchups.filter { !$0.round.contains("Pro Bowl") }.sorted { $0.start < $1.start }
        // Merge conference halves (East/West, AL/NL, AFC/NFC) into one column per stage.
        var order: [String] = []
        for m in matchups where !order.contains(stage(m.round)) { order.append(stage(m.round)) }
        let rounds = order.map { st in
            BracketRound(name: st, matchups: matchups.filter { stage($0.round) == st }.sorted { $0.round < $1.round })
        }
        return Bracket(title: "\(year) \(league.short) Playoffs", rounds: rounds)
    }

    /// "East 1st Round" → "1st Round", "ALDS" → "Division Series", "AFC Wild Card Playoffs" → "Wild Card".
    static func stage(_ round: String) -> String {
        var r = round
        for p in ["Eastern Conference ", "Western Conference ", "East ", "West ", "AFC ", "NFC "] where r.hasPrefix(p) {
            r = String(r.dropFirst(p.count))
        }
        let mlb = ["ALWC": "Wild Card", "NLWC": "Wild Card", "ALDS": "Division Series", "NLDS": "Division Series",
                   "ALCS": "Championship Series", "NLCS": "Championship Series"]
        if let m = mlb[r] { return m }
        r = r.replacingOccurrences(of: " Playoffs", with: "")
        if r == "Final" || r == "Finals" { return "Conference Finals" }
        if r == "Championship" { return "Conference Championships" }
        return r
    }

    // MARK: Individual sports

    static func raceSeason(_ league: LeagueRef) async -> [RaceWeekend] {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let b = await scoreboard(league.path, query: "dates=\(year)")
        return (b?.events ?? []).compactMap { $0.raceWeekend() }.sorted { $0.date < $1.date }
    }

    static func fightCards(_ league: LeagueRef) async -> [FightCard] {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        async let a = scoreboard(league.path, query: "dates=\(year)")
        async let b = scoreboard(league.path, query: "dates=\(year + 1)")
        let all = ((await a)?.events ?? []) + ((await b)?.events ?? [])
        var seen = Set<String>()
        return all.compactMap { $0.fightCard() }.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
    }

    /// Current tournament(s) with full data, plus the season calendar.
    static func tournaments(_ league: LeagueRef) async -> (current: [RawEvent], calendar: [RawCalendarEntry]) {
        let b = await scoreboard(league.path, query: "")
        return (b?.events ?? [], b?.leagues?.first?.calendar ?? [])
    }

    static func tournament(_ league: LeagueRef, startDate: String) async -> RawEvent? {
        guard let d = ESPNDate.parse(startDate) else { return nil }
        let key = keyFormatter("yyyyMMdd").string(from: d.addingTimeInterval(86400))
        let b = await scoreboard(league.path, query: "dates=\(key)")
        return b?.events?.first
    }
}
