import Foundation

// Raw ESPN feed shapes. Every type decodes leniently so one odd field never drops a whole feed.

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
    /// Bool that may arrive as true / "true".
    func flexBool(_ key: Key) -> Bool? {
        if let b = lenient(Bool.self, key) { return b }
        if let s = lenient(String.self, key) { return s == "true" }
        return nil
    }
    /// String that may arrive as a number.
    func flexString(_ key: Key) -> String? {
        if let s = lenient(String.self, key) { return s }
        if let i = lenient(Int.self, key) { return String(i) }
        if let d = lenient(Double.self, key) { return d == d.rounded() ? String(Int(d)) : String(d) }
        return nil
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Lenient decoding helper: decode any listed keys as optional without writing CodingKeys.
struct Fields {
    let c: KeyedDecodingContainer<DynamicKey>
    init(_ d: Decoder) throws { c = try d.container(keyedBy: DynamicKey.self) }
    func get<T: Decodable>(_ t: T.Type, _ k: String) -> T? { c.lenient(t, DynamicKey(stringValue: k)) }
    func str(_ k: String) -> String? { c.flexString(DynamicKey(stringValue: k)) }
    func bool(_ k: String) -> Bool? { c.flexBool(DynamicKey(stringValue: k)) }
    func int(_ k: String) -> Int? {
        if let i = c.lenient(Int.self, DynamicKey(stringValue: k)) { return i }
        if let d = c.lenient(Double.self, DynamicKey(stringValue: k)) { return Int(d) }
        if let s = c.lenient(String.self, DynamicKey(stringValue: k)) { return Int(s) }
        return nil
    }
    func double(_ k: String) -> Double? {
        if let d = c.lenient(Double.self, DynamicKey(stringValue: k)) { return d }
        if let s = c.lenient(String.self, DynamicKey(stringValue: k)) { return Double(s) }
        return nil
    }
}

struct RawHref: Decodable {
    let href: String?
    init(from d: Decoder) throws { href = try Fields(d).str("href") }
    var url: URL? { href.flatMap { URL(string: $0) } }
}

struct RawLogo: Decodable {
    let href: String?
    let rel: [String]?
    init(from d: Decoder) throws { let f = try Fields(d); href = f.str("href"); rel = f.get([String].self, "rel") }
}

struct RawTeam: Decodable {
    let id, abbreviation, displayName, shortDisplayName, name, location, color, alternateColor, logo: String?
    let logos: [RawLogo]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); abbreviation = f.str("abbreviation"); displayName = f.str("displayName")
        shortDisplayName = f.str("shortDisplayName"); name = f.str("name"); location = f.str("location")
        color = f.str("color"); alternateColor = f.str("alternateColor"); logo = f.str("logo")
        logos = f.get([RawLogo].self, "logos")
    }
    var info: TeamInfo? {
        guard let id else { return nil }
        let logoString = logo
            ?? logos?.first(where: { $0.rel?.contains("default") == true })?.href
            ?? logos?.first?.href
        let full = displayName ?? name ?? location ?? ""
        let clean: (String?) -> String? = { $0.map { $0.replacingOccurrences(of: "#", with: "") } }
        return TeamInfo(id: id,
                        abbreviation: abbreviation ?? String(full.prefix(3)).uppercased(),
                        name: full,
                        shortName: shortDisplayName ?? full,
                        colorHex: clean(color), altColorHex: clean(alternateColor),
                        logo: logoString.flatMap { URL(string: $0) })
    }
}

struct RawAthlete: Decodable {
    let id, displayName, shortName, fullName: String?
    let flag: RawHref?
    let headshot: RawHref?
    let team: RawTeam?
    let positionAbbr: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); displayName = f.str("displayName"); shortName = f.str("shortName"); fullName = f.str("fullName")
        flag = f.get(RawHref.self, "flag"); headshot = f.get(RawHref.self, "headshot"); team = f.get(RawTeam.self, "team")
        positionAbbr = f.get(RawPositionRef.self, "position")?.abbreviation
    }
    func model(fallbackID: String?) -> Athlete? {
        guard let n = displayName ?? fullName else { return nil }
        return Athlete(id: id ?? fallbackID ?? n, name: n, shortName: shortName ?? n,
                       flag: flag?.url, headshot: headshot?.url)
    }
}

struct RawPositionRef: Decodable {
    let abbreviation: String?
    init(from d: Decoder) throws { abbreviation = try Fields(d).str("abbreviation") }
}

struct RawScore: Decodable {
    let text: String?
    private struct Obj: Decodable { let displayValue: String?; let value: Double? }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else if let o = try? c.decode(Obj.self) { text = o.displayValue ?? o.value.map { String(Int($0)) } }
        else if let d = try? c.decode(Double.self) { text = String(Int(d)) }
        else { text = nil }
    }
}

struct RawLinescore: Decodable {
    let displayValue: String?
    let value: Double?
    let winner: Bool?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        displayValue = f.str("displayValue"); value = f.double("value"); winner = f.bool("winner")
    }
    var text: String? { displayValue ?? value.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } }
}

struct RawRecord: Decodable {
    let summary: String?
    init(from d: Decoder) throws { summary = try Fields(d).str("summary") }
}

struct RawCompetitor: Decodable {
    let id, homeAway, recordString: String?
    let winner: Bool?
    let order: Int?
    let score: RawScore?
    let team: RawTeam?
    let athlete: RawAthlete?
    let records: [RawRecord]?
    let linescores: [RawLinescore]?
    let seed: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); homeAway = f.str("homeAway"); winner = f.bool("winner"); order = f.int("order")
        score = f.get(RawScore.self, "score"); team = f.get(RawTeam.self, "team"); athlete = f.get(RawAthlete.self, "athlete")
        records = f.get([RawRecord].self, "records"); recordString = f.str("record")
        linescores = f.get([RawLinescore].self, "linescores")
        seed = f.str("seed") ?? f.str("curatedRank")
    }
}

struct RawStatusType: Decodable {
    let state, detail, shortDetail, description, name: String?
    let completed: Bool?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        state = f.str("state"); detail = f.str("detail"); shortDetail = f.str("shortDetail")
        description = f.str("description"); name = f.str("name"); completed = f.bool("completed")
    }
}

struct RawStatus: Decodable {
    let type: RawStatusType?
    let displayClock: String?
    let period: Int?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        type = f.get(RawStatusType.self, "type"); displayClock = f.str("displayClock"); period = f.int("period")
    }
    var state: GameState {
        switch type?.state { case "in": .live; case "post": .post; default: .pre }
    }
}

struct RawText: Decodable {
    let headline, abbreviation, displayName, text, fullName: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        headline = f.str("headline"); abbreviation = f.str("abbreviation"); displayName = f.str("displayName")
        text = f.str("text"); fullName = f.str("fullName")
    }
}

struct RawSeriesCompetitor: Decodable {
    let id: String?
    let wins: Int?
    init(from d: Decoder) throws { let f = try Fields(d); id = f.str("id"); wins = f.int("wins") }
}

struct RawSeries: Decodable {
    let summary: String?
    let completed: Bool?
    let competitors: [RawSeriesCompetitor]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        summary = f.str("summary"); completed = f.bool("completed"); competitors = f.get([RawSeriesCompetitor].self, "competitors")
    }
}

struct RawAddress: Decodable {
    let city, country, state: String?
    init(from d: Decoder) throws { let f = try Fields(d); city = f.str("city"); country = f.str("country"); state = f.str("state") }
}

struct RawVenue: Decodable {
    let fullName: String?
    let address: RawAddress?
    init(from d: Decoder) throws { let f = try Fields(d); fullName = f.str("fullName"); address = f.get(RawAddress.self, "address") }
}

struct RawCompetition: Decodable {
    let id, date, startDate: String?
    let status: RawStatus?
    let competitors: [RawCompetitor]?
    let venue: RawVenue?
    let notes: [RawText]?
    let series: RawSeries?
    let type: RawText?
    let round: RawText?
    let format: RawFormat?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); date = f.str("date"); startDate = f.str("startDate")
        status = f.get(RawStatus.self, "status"); competitors = f.get([RawCompetitor].self, "competitors")
        venue = f.get(RawVenue.self, "venue"); notes = f.get([RawText].self, "notes"); series = f.get(RawSeries.self, "series")
        type = f.get(RawText.self, "type"); round = f.get(RawText.self, "round"); format = f.get(RawFormat.self, "format")
    }

    func game(id: String?, date: String?, fallbackStatus: RawStatus?, competition: String?, path: String?, seasonType: Int?) -> Game? {
        guard let gameID = id ?? self.id,
              let when = ESPNDate.parse(date ?? self.date ?? startDate),
              let comps = competitors else { return nil }
        let sides: [Side] = comps.compactMap { c in
            guard let t = c.team?.info else { return nil }
            return Side(team: t, score: c.score?.text, isHome: c.homeAway == "home", winner: c.winner,
                        record: c.records?.first?.summary ?? c.recordString,
                        linescores: (c.linescores ?? []).compactMap(\.text))
        }
        guard sides.count == 2 else { return nil }
        let home = sides.first(where: \.isHome) ?? sides[0]
        let away = sides.first(where: { !$0.isHome && $0.team.id != home.team.id }) ?? sides[1]
        let st = (status?.type != nil ? status : fallbackStatus)
        let state = st?.state ?? .pre
        var wins: [String: Int] = [:]
        for c in series?.competitors ?? [] { if let id = c.id, let w = c.wins { wins[id] = w } }
        return Game(id: gameID, date: when, state: state,
                    completed: st?.type?.completed ?? (state == .post),
                    detail: st?.type?.detail ?? st?.type?.description ?? "",
                    shortDetail: st?.type?.shortDetail ?? "",
                    home: home, away: away,
                    competition: competition, leaguePath: path,
                    venue: venue?.fullName,
                    note: notes?.first?.headline,
                    seriesSummary: series?.summary,
                    seriesWins: wins,
                    seasonType: seasonType)
    }
}

struct RawFormat: Decodable {
    let periods: Int?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        periods = f.get(RawRegulation.self, "regulation")?.periods
    }
}

struct RawRegulation: Decodable {
    let periods: Int?
    init(from d: Decoder) throws { periods = try Fields(d).int("periods") }
}

struct RawLeague: Decodable {
    let name, abbreviation, slug, shortName: String?
    let logos: [RawLogo]?
    let calendar: [RawCalendarEntry]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        name = f.str("name"); abbreviation = f.str("abbreviation"); slug = f.str("slug"); shortName = f.str("shortName")
        logos = f.get([RawLogo].self, "logos"); calendar = f.get([RawCalendarEntry].self, "calendar")
    }
}

struct RawCalendarEntry: Decodable {
    let label, startDate, endDate, id: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        label = f.str("label"); startDate = f.str("startDate"); endDate = f.str("endDate")
        id = f.get(RawRef.self, "event")?.ref.flatMap { r in
            r.split(separator: "/").last.map { String($0.split(separator: "?").first ?? "") }
        }
    }
}

struct RawRef: Decodable {
    let ref: String?
    init(from d: Decoder) throws { ref = try Fields(d).str("$ref") }
}

struct RawSeason: Decodable {
    let year: Int?
    let type: Int?
    init(from d: Decoder) throws { let f = try Fields(d); year = f.int("year"); type = f.int("type") }
}

struct RawWeek: Decodable {
    let number: Int?
    init(from d: Decoder) throws { number = try Fields(d).int("number") }
}

struct RawGrouping: Decodable {
    let grouping: RawText?
    let competitions: [RawCompetition]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        grouping = f.get(RawText.self, "grouping"); competitions = f.get([RawCompetition].self, "competitions")
    }
}

struct RawEvent: Decodable {
    let id, date, endDate, name, shortName: String?
    let league: RawLeague?
    let status: RawStatus?
    let competitions: [RawCompetition]?
    let season: RawSeason?
    let week: RawWeek?
    let circuit: RawVenue?
    let venue: RawVenue?
    let venues: [RawVenue]?
    let groupings: [RawGrouping]?
    let major: Bool?

    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); date = f.str("date"); endDate = f.str("endDate"); name = f.str("name"); shortName = f.str("shortName")
        league = f.get(RawLeague.self, "league"); status = f.get(RawStatus.self, "status")
        competitions = f.get([RawCompetition].self, "competitions"); season = f.get(RawSeason.self, "season")
        week = f.get(RawWeek.self, "week")
        circuit = f.get(RawVenue.self, "circuit"); venue = f.get(RawVenue.self, "venue"); venues = f.get([RawVenue].self, "venues")
        groupings = f.get([RawGrouping].self, "groupings"); major = f.bool("major")
    }

    func game(competition: String? = nil, path: String? = nil) -> Game? {
        let slugPath: String? = path ?? league?.slug.map { "soccer/\($0)" }
        return competitions?.first?.game(id: id, date: date, fallbackStatus: status,
                                         competition: competition ?? league?.abbreviation ?? league?.name,
                                         path: slugPath, seasonType: season?.type)
    }

    // MARK: Individual sports

    func raceWeekend() -> RaceWeekend? {
        guard let id, let start = ESPNDate.parse(date) else { return nil }
        let sessions: [RaceSession] = (competitions ?? []).compactMap { c in
            guard let sid = c.id, let when = ESPNDate.parse(c.date ?? c.startDate) else { return nil }
            let results = (c.competitors ?? []).compactMap { x -> RaceResult? in
                guard let a = x.athlete?.model(fallbackID: x.id) else { return nil }
                return RaceResult(position: x.order ?? 99, athlete: a, winner: x.winner ?? false)
            }.sorted { $0.position < $1.position }
            return RaceSession(id: sid, name: c.type?.abbreviation ?? c.type?.text ?? "Session", date: when,
                               state: c.status?.state ?? .pre, detail: c.status?.type?.detail ?? "", results: results)
        }
        let loc = [circuit?.address?.city, circuit?.address?.country].compactMap { $0 }.joined(separator: ", ")
        return RaceWeekend(id: id, name: name ?? "", shortName: shortName ?? name ?? "", date: start,
                           endDate: ESPNDate.parse(endDate), circuit: circuit?.fullName,
                           location: loc.isEmpty ? nil : loc, state: status?.state ?? .pre, sessions: sessions)
    }

    func golfTournament() -> GolfTournament? {
        guard let id, let start = ESPNDate.parse(date) else { return nil }
        let comp = competitions?.first
        let raw = (comp?.competitors ?? []).sorted { ($0.order ?? 999) < ($1.order ?? 999) }
        var players: [GolfPlayer] = []
        let scores = raw.map { $0.score?.text ?? "" }
        for (i, x) in raw.enumerated() {
            guard let a = x.athlete?.model(fallbackID: x.id) else { continue }
            let s = scores[i]
            let firstIndex = scores.firstIndex(of: s) ?? i
            let tied = scores.filter { $0 == s }.count > 1
            let pos = s.isEmpty ? "–" : (tied ? "T\(firstIndex + 1)" : "\(firstIndex + 1)")
            players.append(GolfPlayer(position: pos, athlete: a, toPar: s.isEmpty ? "–" : s,
                                      rounds: (x.linescores ?? []).compactMap(\.text)))
        }
        let st = comp?.status ?? status
        return GolfTournament(id: id, name: name ?? "", date: start, endDate: ESPNDate.parse(endDate),
                              state: st?.state ?? .pre, detail: st?.type?.detail ?? "", players: players)
    }

    func tennisTournament() -> TennisTournament? {
        guard let id, let start = ESPNDate.parse(date) else { return nil }
        var matches: [TennisMatch] = []
        for g in groupings ?? [] {
            let draw = g.grouping?.displayName ?? "Draw"
            for c in g.competitions ?? [] {
                guard let mid = c.id, let when = ESPNDate.parse(c.date ?? c.startDate) else { continue }
                let lines: [TennisLine] = (c.competitors ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap { x in
                    guard let a = x.athlete?.model(fallbackID: x.id) else { return nil }
                    let ls = x.linescores ?? []
                    return TennisLine(athlete: a, sets: ls.compactMap(\.text), setWins: ls.map { $0.winner ?? false },
                                      winner: x.winner, seed: x.seed)
                }
                guard lines.count == 2 else { continue }
                matches.append(TennisMatch(id: mid, round: c.round?.displayName ?? "", draw: draw, date: when,
                                           state: c.status?.state ?? .pre, detail: c.status?.type?.shortDetail ?? "",
                                           players: lines))
            }
        }
        return TennisTournament(id: id, name: name ?? "", date: start, endDate: ESPNDate.parse(endDate),
                                state: status?.state ?? .pre, major: major ?? false,
                                venue: venue?.fullName, matches: matches)
    }

    func fightCard() -> FightCard? {
        guard let id, let start = ESPNDate.parse(date) else { return nil }
        let fights: [Fight] = (competitions ?? []).compactMap { c in
            guard let fid = c.id, let when = ESPNDate.parse(c.date ?? c.startDate) else { return nil }
            let fighters: [Fighter] = (c.competitors ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap { x in
                guard let a = x.athlete?.model(fallbackID: x.id) else { return nil }
                return Fighter(athlete: a, record: x.records?.first?.summary, winner: x.winner)
            }
            guard fighters.count == 2 else { return nil }
            return Fight(id: fid, weightClass: c.type?.abbreviation ?? "", date: when,
                         state: c.status?.state ?? .pre, detail: c.status?.type?.shortDetail ?? "",
                         round: c.status?.period, clock: c.status?.displayClock, rounds: c.format?.periods,
                         fighters: fighters)
        }
        return FightCard(id: id, name: name ?? "", date: start, state: status?.state ?? .pre,
                         venue: (venues?.first ?? venue)?.fullName, fights: fights.reversed())
    }
}

struct RawSchedule: Decodable {
    let events: [RawEvent]?
    let team: RawTeam?
}

struct RawScoreboard: Decodable {
    let leagues: [RawLeague]?
    let events: [RawEvent]?
}

struct RawScorePanel: Decodable {
    struct Block: Decodable {
        let leagues: [RawLeague]?
        let events: [RawEvent]?
    }
    let scores: [Block]?
}

// Standings

struct RawStat: Decodable {
    let name, type, displayValue: String?
    let value: Double?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        name = f.str("name"); type = f.str("type"); displayValue = f.str("displayValue"); value = f.double("value")
    }
}

struct RawNote: Decodable {
    let color, description: String?
    init(from d: Decoder) throws { let f = try Fields(d); color = f.str("color"); description = f.str("description") }
}

struct RawEntry: Decodable {
    let team: RawTeam?
    let athlete: RawAthlete?
    let stats: [RawStat]?
    let note: RawNote?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        team = f.get(RawTeam.self, "team"); athlete = f.get(RawAthlete.self, "athlete")
        stats = f.get([RawStat].self, "stats"); note = f.get(RawNote.self, "note")
    }

    var keyed: (display: [String: String], values: [String: Double]) {
        var display: [String: String] = [:]
        var values: [String: Double] = [:]
        for s in stats ?? [] {
            guard let key = s.name ?? s.type else { continue }
            if let v = s.displayValue { display[key] = v }
            if let v = s.value { values[key] = v }
        }
        return (display, values)
    }
}

struct RawStandingsBlock: Decodable {
    let entries: [RawEntry]?
    init(from d: Decoder) throws { entries = try Fields(d).get([RawEntry].self, "entries") }
}

struct RawSeasonYears: Decodable {
    let seasonYears: String?
    let year: Int?
    init(from d: Decoder) throws { let f = try Fields(d); seasonYears = f.str("seasonYears"); year = f.int("year") }
}

final class RawStandingsNode: Decodable {
    let name: String?
    let children: [RawStandingsNode]?
    let standings: RawStandingsBlock?
    let seasons: [RawSeasonYears]?
    required init(from d: Decoder) throws {
        let f = try Fields(d)
        name = f.str("name"); children = f.get([RawStandingsNode].self, "children")
        standings = f.get(RawStandingsBlock.self, "standings"); seasons = f.get([RawSeasonYears].self, "seasons")
    }
}

// Leaders

struct RawLeader: Decodable {
    let displayValue: String?
    let value: Double?
    let athlete: RawAthlete?
    let team: RawTeam?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        displayValue = f.str("displayValue"); value = f.double("value")
        athlete = f.get(RawAthlete.self, "athlete"); team = f.get(RawTeam.self, "team")
    }
}

struct RawLeaderCat: Decodable {
    let name, displayName: String?
    let leaders: [RawLeader]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        name = f.str("name"); displayName = f.str("displayName"); leaders = f.get([RawLeader].self, "leaders")
    }

    func category(soccer: Bool) -> LeaderCategory? {
        guard let name, let leaders, !leaders.isEmpty else { return nil }
        let items: [Leader] = leaders.enumerated().compactMap { i, l in
            guard let athlete = l.athlete, let n = athlete.displayName ?? athlete.fullName else { return nil }
            let team = (l.team ?? athlete.team)?.info
            var value = l.displayValue ?? ""
            var detail: String? = athlete.positionAbbr
            if soccer {
                value = l.value.map { String(Int($0)) } ?? value
                if let dv = l.displayValue, let m = dv.split(separator: ",").first?.split(separator: ":").last {
                    detail = "\(m.trimmingCharacters(in: .whitespaces)) matches"
                }
            }
            return Leader(id: "\(name)-\(athlete.id ?? String(i))", name: n, team: team, value: value,
                          detail: detail, headshot: athlete.headshot?.url)
        }
        let title = (displayName ?? name).replacingOccurrences(of: "Leaders", with: "").trimmingCharacters(in: .whitespaces)
        return LeaderCategory(id: name, title: title, leaders: items)
    }
}

struct RawSoccerStats: Decodable { let stats: [RawLeaderCat]? }
struct RawUSBlock: Decodable { let categories: [RawLeaderCat]? }
struct RawUSLeaders: Decodable { let leaders: RawUSBlock? }

// Teams

struct RawTeamWrap: Decodable { let team: RawTeam? }
struct RawTeamsLeague: Decodable { let teams: [RawTeamWrap]? }
struct RawTeamsSport: Decodable { let leagues: [RawTeamsLeague]? }
struct RawTeamsList: Decodable { let sports: [RawTeamsSport]? }

struct RawTeamDetail: Decodable {
    let team: RawTeam?
    let record: String?
    let standingSummary: String?
    let venue: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        let teamField = f.get(RawTeam.self, "team")
        team = teamField
        // record/summary/venue live inside "team"
        let inner = try? f.c.nestedContainer(keyedBy: DynamicKey.self, forKey: DynamicKey(stringValue: "team"))
        standingSummary = inner?.flexString(DynamicKey(stringValue: "standingSummary"))
        if let rec = try? inner?.nestedContainer(keyedBy: DynamicKey.self, forKey: DynamicKey(stringValue: "record")),
           let items = rec.lenient([RawRecord].self, DynamicKey(stringValue: "items")) {
            record = items.first?.summary
        } else { record = nil }
        if let fr = try? inner?.nestedContainer(keyedBy: DynamicKey.self, forKey: DynamicKey(stringValue: "franchise")) {
            venue = fr.lenient(RawVenue.self, DynamicKey(stringValue: "venue"))?.fullName
        } else { venue = nil }
    }
}

// Roster

struct RawRosterStat: Decodable {
    let name: String?
    let value: Double?
    init(from d: Decoder) throws { let f = try Fields(d); name = f.str("name"); value = f.double("value") }
}
struct RawRosterCat: Decodable { let stats: [RawRosterStat]? }
struct RawRosterSplits: Decodable { let categories: [RawRosterCat]? }
struct RawRosterStats: Decodable { let splits: RawRosterSplits? }

struct RawRosterAthlete: Decodable {
    let id, displayName, jersey, age: String?
    let position: RawPositionRef?
    let headshot: RawHref?
    let flag: RawHref?
    let statistics: RawRosterStats?
    let items: [RawRosterAthlete]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); displayName = f.str("displayName"); jersey = f.str("jersey"); age = f.str("age")
        position = f.get(RawPositionRef.self, "position"); headshot = f.get(RawHref.self, "headshot")
        flag = f.get(RawHref.self, "flag"); statistics = f.get(RawRosterStats.self, "statistics")
        items = f.get([RawRosterAthlete].self, "items")
    }
    var player: Player? {
        guard let id, let displayName else { return nil }
        var stats: [String: Double] = [:]
        for c in statistics?.splits?.categories ?? [] {
            for s in c.stats ?? [] { if let n = s.name, let v = s.value { stats[n] = v } }
        }
        return Player(id: id, name: displayName, jersey: jersey, position: position?.abbreviation,
                      headshot: headshot?.url, flag: flag?.url, age: age, stats: stats)
    }
}

struct RawRoster: Decodable {
    let athletes: [RawRosterAthlete]?
}

// Summary

struct RawKeyEvent: Decodable {
    let id, text: String?
    let type: RawText?
    let clock: RawText?
    let clockValue: String?
    let team: RawTeam?
    let periodNumber: Int?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); text = f.str("text"); type = f.get(RawText.self, "type")
        clock = f.get(RawText.self, "clock"); team = f.get(RawTeam.self, "team")
        clockValue = f.get(RawClock.self, "clock")?.displayValue
        periodNumber = f.get(RawPeriod.self, "period")?.number
    }
}

struct RawClock: Decodable {
    let displayValue: String?
    init(from d: Decoder) throws { displayValue = try Fields(d).str("displayValue") }
}

struct RawPeriod: Decodable {
    let number: Int?
    init(from d: Decoder) throws { number = try Fields(d).int("number") }
}

struct RawBoxStat: Decodable {
    let name, label, abbreviation, displayValue: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        name = f.str("name"); label = f.str("label"); abbreviation = f.str("abbreviation"); displayValue = f.str("displayValue")
    }
}

struct RawBoxTeam: Decodable {
    let team: RawTeam?
    let statistics: [RawBoxStat]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        team = f.get(RawTeam.self, "team"); statistics = f.get([RawBoxStat].self, "statistics")
    }
}

struct RawBox: Decodable {
    let teams: [RawBoxTeam]?
    init(from d: Decoder) throws { teams = try Fields(d).get([RawBoxTeam].self, "teams") }
}

struct RawTeamLeaders: Decodable {
    let team: RawTeam?
    let leaders: [RawLeaderCat]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        team = f.get(RawTeam.self, "team"); leaders = f.get([RawLeaderCat].self, "leaders")
    }
}

struct RawSummaryHeader: Decodable {
    let id: String?
    let league: RawLeague?
    let competitions: [RawCompetition]?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        id = f.str("id"); league = f.get(RawLeague.self, "league"); competitions = f.get([RawCompetition].self, "competitions")
    }
}

struct RawSummary: Decodable {
    let header: RawSummaryHeader?
    let keyEvents: [RawKeyEvent]?
    let scoringPlays: [RawKeyEvent]?
    let boxscore: RawBox?
    let leaders: [RawTeamLeaders]?
    let venueName: String?
    init(from d: Decoder) throws {
        let f = try Fields(d)
        header = f.get(RawSummaryHeader.self, "header"); keyEvents = f.get([RawKeyEvent].self, "keyEvents")
        scoringPlays = f.get([RawKeyEvent].self, "scoringPlays"); boxscore = f.get(RawBox.self, "boxscore")
        leaders = f.get([RawTeamLeaders].self, "leaders")
        venueName = f.get(RawGameInfo.self, "gameInfo")?.venue?.fullName
    }
}

struct RawGameInfo: Decodable {
    let venue: RawVenue?
    init(from d: Decoder) throws { venue = try Fields(d).get(RawVenue.self, "venue") }
}

// MARK: - Dates

enum ESPNDate {
    private static let formatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mm:ss.SSSX",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        for f in formatters { if let d = f.date(from: s) { return d } }
        return nil
    }
}
