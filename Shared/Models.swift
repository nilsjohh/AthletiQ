import Foundation

// MARK: - Teams & games

struct TeamInfo: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let abbreviation: String
    let name: String
    let shortName: String
    let colorHex: String?
    let altColorHex: String?
    let logo: URL?

    /// ESPN serves a dark-background variant for most crests.
    var darkLogo: URL? {
        guard let s = logo?.absoluteString, s.contains("/500/") else { return nil }
        return URL(string: s.replacingOccurrences(of: "/500/", with: "/500-dark/"))
    }
}

enum GameState: String, Hashable, Sendable, Codable { case pre, live, post }

enum Outcome: String, Sendable, Codable { case win = "W", draw = "D", loss = "L" }

struct Side: Hashable, Sendable, Codable {
    var team: TeamInfo
    var score: String?
    var isHome: Bool
    var winner: Bool?
    var record: String?
    var linescores: [String] = []
    var scoreValue: Double? {
        guard let s = score else { return nil }
        if let d = Double(s) { return d }
        // cricket "278/8"
        return s.split(separator: "/").first.flatMap { Double($0) }
    }
}

struct Game: Hashable, Sendable, Identifiable, Codable {
    var id: String
    var date: Date
    var state: GameState
    var completed: Bool
    var detail: String
    var shortDetail: String
    var home: Side
    var away: Side
    var competition: String?
    var leaguePath: String?
    var venue: String?
    /// e.g. "World Series - Game 4"
    var note: String?
    /// e.g. "MIL leads series 3-1"
    var seriesSummary: String?
    var seriesWins: [String: Int] = [:]
    var seasonType: Int?

    func side(of teamID: String) -> Side? {
        home.team.id == teamID ? home : (away.team.id == teamID ? away : nil)
    }

    func opponent(of teamID: String) -> Side? {
        home.team.id == teamID ? away : (away.team.id == teamID ? home : nil)
    }

    func outcome(for teamID: String) -> Outcome? {
        guard state == .post, completed,
              let me = side(of: teamID), let them = opponent(of: teamID),
              let a = me.scoreValue, let b = them.scoreValue else {
            if state == .post, let me = side(of: teamID), let w = me.winner { return w ? .win : .loss }
            return nil
        }
        if a > b { return .win }
        if a < b { return .loss }
        if me.winner == true { return .win }
        if them.winner == true { return .loss }
        return .draw
    }

    var hasScore: Bool { state != .pre && home.score != nil && away.score != nil }

    var liveLabel: String { shortDetail.isEmpty ? "LIVE" : shortDetail }

    func isLoser(_ side: Side) -> Bool {
        guard state == .post else { return false }
        let other = side.team.id == home.team.id ? away : home
        if let w = side.winner, let ow = other.winner, w != ow { return !w }
        guard let a = side.scoreValue, let b = other.scoreValue else { return false }
        return a < b
    }

    /// Round name from the note, e.g. "World Series".
    var roundName: String? {
        guard let note else { return nil }
        if let r = note.range(of: " - ") { return String(note[..<r.lowerBound]) }
        return note
    }
}

// MARK: - Standings

struct StandingRow: Hashable, Sendable, Identifiable, Codable {
    let team: TeamInfo
    var rank: Int
    let display: [String: String]
    let note: String?
    let noteColorHex: String?
    var id: String { team.id }
    func value(_ key: String) -> String {
        let v = display[key] ?? ""
        return v.trimmingCharacters(in: .whitespaces).isEmpty ? "–" : v
    }
}

struct StandingsGroup: Hashable, Sendable, Identifiable, Codable {
    let name: String
    let rows: [StandingRow]
    var id: String { name }

    func window(around teamID: String, count: Int) -> [StandingRow] {
        guard let i = rows.firstIndex(where: { $0.team.id == teamID }) else { return Array(rows.prefix(count)) }
        var start = max(0, i - count / 2)
        start = min(start, max(0, rows.count - count))
        return Array(rows[start..<min(rows.count, start + count)])
    }
}

struct StandingColumn: Identifiable, Hashable {
    let key: String
    let label: String
    let width: CGFloat
    var emphasized = false
    var id: String { key }

    func format(_ raw: String) -> String {
        if let comma = raw.firstIndex(of: ",") { return String(raw[..<comma]) }
        return raw
    }

    static func columns(for style: TableStyle) -> [StandingColumn] {
        switch style {
        case .soccer:
            [.init(key: "gamesPlayed", label: "P", width: 30), .init(key: "wins", label: "W", width: 30),
             .init(key: "ties", label: "D", width: 30), .init(key: "losses", label: "L", width: 30),
             .init(key: "pointsFor", label: "GF", width: 34), .init(key: "pointsAgainst", label: "GA", width: 34),
             .init(key: "pointDifferential", label: "GD", width: 40),
             .init(key: "points", label: "PTS", width: 42, emphasized: true)]
        case .hockey:
            [.init(key: "gamesPlayed", label: "GP", width: 34), .init(key: "wins", label: "W", width: 32),
             .init(key: "losses", label: "L", width: 32), .init(key: "otLosses", label: "OTL", width: 38),
             .init(key: "points", label: "PTS", width: 42, emphasized: true),
             .init(key: "pointsFor", label: "GF", width: 36), .init(key: "pointsAgainst", label: "GA", width: 36),
             .init(key: "pointDifferential", label: "DIFF", width: 44),
             .init(key: "Last Ten Games", label: "L10", width: 58), .init(key: "streak", label: "STRK", width: 46)]
        case .basketball:
            [.init(key: "wins", label: "W", width: 32, emphasized: true), .init(key: "losses", label: "L", width: 32, emphasized: true),
             .init(key: "winPercent", label: "PCT", width: 48), .init(key: "gamesBehind", label: "GB", width: 40),
             .init(key: "avgPointsFor", label: "PPG", width: 50), .init(key: "avgPointsAgainst", label: "OPP", width: 50),
             .init(key: "differential", label: "DIFF", width: 48), .init(key: "Last Ten Games", label: "L10", width: 50),
             .init(key: "streak", label: "STRK", width: 46)]
        case .americanFootball:
            [.init(key: "wins", label: "W", width: 32, emphasized: true), .init(key: "losses", label: "L", width: 32, emphasized: true),
             .init(key: "ties", label: "T", width: 28), .init(key: "winPercent", label: "PCT", width: 50),
             .init(key: "pointsFor", label: "PF", width: 42), .init(key: "pointsAgainst", label: "PA", width: 42),
             .init(key: "differential", label: "DIFF", width: 46), .init(key: "streak", label: "STRK", width: 46)]
        case .baseball:
            [.init(key: "wins", label: "W", width: 34, emphasized: true), .init(key: "losses", label: "L", width: 34, emphasized: true),
             .init(key: "winPercent", label: "PCT", width: 50), .init(key: "gamesBehind", label: "GB", width: 42),
             .init(key: "pointsFor", label: "RS", width: 42), .init(key: "pointsAgainst", label: "RA", width: 42),
             .init(key: "differential", label: "DIFF", width: 46), .init(key: "Last Ten Games", label: "L10", width: 50),
             .init(key: "streak", label: "STRK", width: 46)]
        case .rugby:
            [.init(key: "gamesPlayed", label: "P", width: 30), .init(key: "wins", label: "W", width: 30),
             .init(key: "ties", label: "D", width: 30), .init(key: "losses", label: "L", width: 30),
             .init(key: "pointsFor", label: "PF", width: 40), .init(key: "pointsAgainst", label: "PA", width: 40),
             .init(key: "pointDifferential", label: "PD", width: 42), .init(key: "bonusPoints", label: "BP", width: 32),
             .init(key: "points", label: "PTS", width: 42, emphasized: true)]
        case .lacrosse:
            [.init(key: "gamesPlayed", label: "GP", width: 34), .init(key: "wins", label: "W", width: 32, emphasized: true),
             .init(key: "losses", label: "L", width: 32), .init(key: "winPercent", label: "PCT", width: 48),
             .init(key: "pointsFor", label: "SF", width: 40), .init(key: "pointsAgainst", label: "SA", width: 40),
             .init(key: "points", label: "PTS", width: 40, emphasized: true)]
        }
    }

    /// Columns that actually have data in this table.
    static func visible(for style: TableStyle, rows: [StandingRow]) -> [StandingColumn] {
        columns(for: style).filter { c in rows.contains { ($0.display[c.key] ?? "").trimmingCharacters(in: .whitespaces) != "" } }
    }

    /// Compact set for widgets.
    static func compact(for style: TableStyle) -> [StandingColumn] {
        switch style {
        case .soccer, .rugby: [.init(key: "gamesPlayed", label: "P", width: 22), .init(key: "pointDifferential", label: "GD", width: 30),
                               .init(key: "points", label: "PTS", width: 30, emphasized: true)]
        case .hockey: [.init(key: "gamesPlayed", label: "GP", width: 24), .init(key: "wins", label: "W", width: 24),
                       .init(key: "points", label: "PTS", width: 30, emphasized: true)]
        default: [.init(key: "wins", label: "W", width: 26, emphasized: true), .init(key: "losses", label: "L", width: 26),
                  .init(key: "winPercent", label: "PCT", width: 40)]
        }
    }
}

// MARK: - Leaders & players

struct Leader: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let team: TeamInfo?
    let value: String
    let detail: String?
    let headshot: URL?
}

struct LeaderCategory: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let title: String
    let leaders: [Leader]
}

struct Player: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let jersey: String?
    let position: String?
    let headshot: URL?
    let flag: URL?
    let age: String?
    var stats: [String: Double] = [:]
}

// MARK: - Team detail

struct TeamDetail: Hashable, Sendable, Codable {
    let info: TeamInfo
    let record: String?
    let standingSummary: String?
    let venue: String?
    let location: String?
}

// MARK: - Game detail

struct KeyEvent: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let clock: String
    let type: String
    let text: String
    let teamID: String?
}

struct StatLine: Hashable, Sendable, Identifiable, Codable {
    let label: String
    let home: String
    let away: String
    var id: String { label }
}

struct PerformerPair: Hashable, Sendable, Identifiable, Codable {
    let category: String
    let home: Leader?
    let away: Leader?
    var id: String { category }
}

struct GameDetail: Hashable, Sendable {
    var game: Game
    var keyEvents: [KeyEvent]
    var teamStats: [StatLine]
    var performers: [PerformerPair]
    var periodLabels: [String]
    var lineups: [Lineup] = []

    func lineup(for teamID: String) -> Lineup? { lineups.first { $0.teamID == teamID } }
}

// MARK: - Lineups

enum LineupStyle: String, Hashable, Sendable, Codable { case pitch, court, groups }

struct LineupPlayer: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let shortName: String
    let jersey: String?
    let position: String?       // abbreviation, e.g. "G", "CD-L", "F"
    let positionName: String?   // e.g. "Center Left Defender"
    let formationPlace: Int?
    let subbedIn: Bool
    let subbedOut: Bool
    let headshot: URL?

    /// Surname for compact labels ("Ødegaard").
    var label: String {
        let parts = name.split(separator: " ")
        return parts.count > 1 ? String(parts.dropFirst().joined(separator: " ")) : name
    }
}

struct LineupGroup: Hashable, Sendable, Identifiable, Codable {
    let name: String
    let players: [LineupPlayer]
    var id: String { name }
}

struct Lineup: Hashable, Sendable, Codable {
    let teamID: String
    let style: LineupStyle
    let formation: String?
    let starters: [LineupPlayer]
    let bench: [LineupPlayer]
    var groups: [LineupGroup] = []

    /// Football: outfield rows from back to front (left → right within a row), following the formation.
    var pitchRows: [[LineupPlayer]] {
        let keepers = starters.filter { ($0.positionName ?? "").lowercased().contains("goalkeeper") || $0.formationPlace == 1 }
        let outfield = starters.filter { p in !keepers.contains(where: { $0.id == p.id }) }
        let counts = (formation ?? "").split(separator: "-").compactMap { Int($0) }
        let sorted = outfield.sorted { (Self.depth($0), Self.lateral($0)) < (Self.depth($1), Self.lateral($1)) }
        var rows: [[LineupPlayer]] = [Array(keepers.prefix(1))]
        if counts.reduce(0, +) == sorted.count {
            var i = 0
            for c in counts {
                rows.append(Array(sorted[i..<i + c]).sorted { Self.lateral($0) < Self.lateral($1) })
                i += c
            }
        } else {
            // No usable formation: group by line.
            let byDepth = Dictionary(grouping: sorted) { Self.depth($0) }
            for d in byDepth.keys.sorted() { rows.append((byDepth[d] ?? []).sorted { Self.lateral($0) < Self.lateral($1) }) }
        }
        return rows.filter { !$0.isEmpty }
    }

    static func depth(_ p: LineupPlayer) -> Int {
        let n = (p.positionName ?? "").lowercased()
        if n.contains("goalkeeper") { return 0 }
        if n.contains("defender") || n.contains("back") || n.contains("sweeper") { return 1 }
        if n.contains("defensive midfielder") { return 2 }
        if n.contains("attacking") || n.contains("winger") { return 4 }
        if n.contains("midfielder") { return 3 }
        if n.contains("forward") || n.contains("striker") { return 5 }
        return 3
    }

    static func lateral(_ p: LineupPlayer) -> Double {
        let n = (p.positionName ?? "").lowercased()
        if n.contains("center left") || n.contains("centre left") { return -0.5 }
        if n.contains("center right") || n.contains("centre right") { return 0.5 }
        if n.contains("left") { return -1 }
        if n.contains("right") { return 1 }
        return 0
    }
}

// MARK: - Individual sports

struct Athlete: Hashable, Sendable, Codable {
    let id: String
    let name: String
    let shortName: String
    let flag: URL?
    let headshot: URL?
}

extension Athlete {
    /// ESPN headshot, falling back to the standard per-sport headshot path.
    func photo(_ leaguePath: String) -> URL? {
        if let headshot { return headshot }
        let folder: String
        switch leaguePath.split(separator: "/").first {
        case "mma": folder = "mma"
        case "racing": folder = "rpm"
        case "golf": folder = "golf"
        case "tennis": folder = "tennis"
        default: return nil
        }
        return URL(string: "https://a.espncdn.com/i/headshots/\(folder)/players/full/\(id).png")
    }
}

struct RaceResult: Hashable, Sendable, Identifiable, Codable {
    let position: Int
    let athlete: Athlete
    let winner: Bool
    var id: String { athlete.id }
}

struct RaceSession: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let date: Date
    let state: GameState
    let detail: String
    let results: [RaceResult]
}

struct RaceWeekend: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let shortName: String
    let date: Date
    let endDate: Date?
    let circuit: String?
    let location: String?
    let state: GameState
    let sessions: [RaceSession]
    var mainSession: RaceSession? { sessions.last { $0.name.lowercased().contains("race") } ?? sessions.last }
}

struct DriverStanding: Hashable, Sendable, Identifiable, Codable {
    let rank: Int
    let name: String
    let flag: URL?
    let logo: URL?
    let points: String
    var id: String { "\(rank)-\(name)" }
}

struct GolfPlayer: Hashable, Sendable, Identifiable, Codable {
    let position: String
    let athlete: Athlete
    let toPar: String
    let rounds: [String]
    var id: String { athlete.id }
}

struct GolfTournament: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let date: Date
    let endDate: Date?
    let state: GameState
    let detail: String
    let players: [GolfPlayer]
}

struct TennisLine: Hashable, Sendable, Codable {
    let athlete: Athlete
    let sets: [String]
    let setWins: [Bool]
    let winner: Bool?
    let seed: String?
}

struct TennisMatch: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let round: String
    let draw: String
    let date: Date
    let state: GameState
    let detail: String
    let players: [TennisLine]
}

struct TennisTournament: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let date: Date
    let endDate: Date?
    let state: GameState
    let major: Bool
    let venue: String?
    let matches: [TennisMatch]
    var draws: [String] { var seen = Set<String>(); return matches.map(\.draw).filter { seen.insert($0).inserted } }
}

struct Fighter: Hashable, Sendable, Codable {
    let athlete: Athlete
    let record: String?
    let winner: Bool?
}

struct Fight: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let weightClass: String
    let date: Date
    let state: GameState
    let detail: String
    let round: Int?
    let clock: String?
    let rounds: Int?
    let fighters: [Fighter]
}

struct FightCard: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let name: String
    let date: Date
    let state: GameState
    let venue: String?
    /// Main event first.
    let fights: [Fight]
}

// MARK: - Playoffs

struct SeriesMatchup: Hashable, Sendable, Identifiable {
    let id: String
    let round: String
    let teams: [TeamInfo]
    let wins: [Int]
    let summary: String
    let games: [Game]
    let completed: Bool
    let winnerID: String?
    let start: Date
}

struct BracketRound: Hashable, Sendable, Identifiable {
    let name: String
    let matchups: [SeriesMatchup]
    var id: String { name }
}

struct Bracket: Hashable, Sendable {
    let title: String
    let rounds: [BracketRound]
    var isLive: Bool { rounds.contains { $0.matchups.contains { !$0.completed } } }
    var finalMatchup: SeriesMatchup? { rounds.last?.matchups.first }
}
