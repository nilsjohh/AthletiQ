import Foundation

/// How a league's data is shaped, which decides the screens it gets.
enum LeagueKind: String, Codable, Hashable, Sendable {
    case team      // fixtures, standings, team pages
    case racing    // race weekends + driver/constructor standings
    case golf      // tournaments + leaderboards
    case tennis    // tournaments + draws
    case mma       // fight cards
    case cricket   // live/recent matches only
}

/// Table flavour for standings columns.
enum TableStyle: String, Codable, Hashable, Sendable {
    case soccer, basketball, hockey, americanFootball, baseball, rugby, lacrosse
}

enum PatternKind: String, Codable, Hashable, Sendable {
    case pitch, court, gridiron, diamond, rink, rugby, track, golf, tennis, octagon, cricket, lacrosse
}

enum SportID: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case football, basketball, americanFootball, baseball, hockey, rugby, motorsport, golf, tennis, mma, cricket, lacrosse

    var id: String { rawValue }

    var name: String {
        switch self {
        case .football: "Football"
        case .basketball: "Basketball"
        case .americanFootball: "American Football"
        case .baseball: "Baseball"
        case .hockey: "Hockey"
        case .rugby: "Rugby"
        case .motorsport: "Motorsport"
        case .golf: "Golf"
        case .tennis: "Tennis"
        case .mma: "MMA"
        case .cricket: "Cricket"
        case .lacrosse: "Lacrosse"
        }
    }

    var symbol: String {
        switch self {
        case .football: "soccerball"
        case .basketball: "basketball.fill"
        case .americanFootball: "football.fill"
        case .baseball: "baseball.fill"
        case .hockey: "hockey.puck.fill"
        case .rugby: "figure.rugby"
        case .motorsport: "flag.checkered"
        case .golf: "figure.golf"
        case .tennis: "tennis.racket"
        case .mma: "figure.martial.arts"
        case .cricket: "cricket.ball.fill"
        case .lacrosse: "figure.lacrosse"
        }
    }

    /// Theme colours (hex) — primary is the hero colour, accent is used for highlights.
    var primaryHex: String {
        switch self {
        case .football: "0E7A3E"
        case .basketball: "E8590C"
        case .americanFootball: "6B3E1D"
        case .baseball: "1D3F8F"
        case .hockey: "0B6FA4"
        case .rugby: "1F6B3A"
        case .motorsport: "D40000"
        case .golf: "2E7D32"
        case .tennis: "8DB600"
        case .mma: "A50E0E"
        case .cricket: "0D5C3F"
        case .lacrosse: "5B3FB8"
        }
    }

    var accentHex: String {
        switch self {
        case .football: "34D399"
        case .basketball: "FFA94D"
        case .americanFootball: "D9A066"
        case .baseball: "F25C54"
        case .hockey: "7DD3FC"
        case .rugby: "86EFAC"
        case .motorsport: "FF6B6B"
        case .golf: "A7F3D0"
        case .tennis: "E6FF5C"
        case .mma: "FFD43B"
        case .cricket: "6EE7B7"
        case .lacrosse: "C4B5FD"
        }
    }

    var pattern: PatternKind {
        switch self {
        case .football: .pitch
        case .basketball: .court
        case .americanFootball: .gridiron
        case .baseball: .diamond
        case .hockey: .rink
        case .rugby: .rugby
        case .motorsport: .track
        case .golf: .golf
        case .tennis: .tennis
        case .mma: .octagon
        case .cricket: .cricket
        case .lacrosse: .lacrosse
        }
    }

    var leagues: [LeagueRef] { Catalog.leagues.filter { $0.sport == self } }
}

struct LeagueRef: Hashable, Identifiable, Codable, Sendable {
    let sport: SportID
    /// ESPN path, e.g. "soccer/eng.1".
    let path: String
    let name: String
    let short: String
    let kind: LeagueKind
    let colorHex: String
    /// Months (1–12) when the postseason runs; enables the playoffs bracket.
    var playoffMonths: [Int] = []
    var region: String = ""

    var id: String { path }
    var isSoccer: Bool { path.hasPrefix("soccer/") }
    var isCollege: Bool { path.contains("college") }
    var slug: String { String(path.split(separator: "/").last ?? "") }
    var sportPath: String { String(path.split(separator: "/").first ?? "") }
    var hasBracket: Bool { !playoffMonths.isEmpty }

    var tableStyle: TableStyle {
        switch sport {
        case .football: .soccer
        case .basketball: .basketball
        case .hockey: .hockey
        case .americanFootball: .americanFootball
        case .baseball: .baseball
        case .rugby: .rugby
        default: .lacrosse
        }
    }
}

enum Catalog {
    static func L(_ sport: SportID, _ path: String, _ name: String, _ short: String, _ color: String,
                  kind: LeagueKind = .team, playoffs: [Int] = [], region: String = "") -> LeagueRef {
        LeagueRef(sport: sport, path: path, name: name, short: short, kind: kind, colorHex: color,
                  playoffMonths: playoffs, region: region)
    }

    static let leagues: [LeagueRef] = [
        // Football
        L(.football, "soccer/eng.1", "Premier League", "PL", "37003C", region: "England"),
        L(.football, "soccer/esp.1", "LaLiga", "LaLiga", "E8372C", region: "Spain"),
        L(.football, "soccer/ita.1", "Serie A", "Serie A", "0B3A8C", region: "Italy"),
        L(.football, "soccer/ger.1", "Bundesliga", "BL", "D20515", region: "Germany"),
        L(.football, "soccer/fra.1", "Ligue 1", "L1", "0E1C4D", region: "France"),
        L(.football, "soccer/uefa.champions", "Champions League", "UCL", "0A1A4F", region: "Europe"),
        L(.football, "soccer/uefa.europa", "Europa League", "UEL", "E36B0A", region: "Europe"),
        L(.football, "soccer/uefa.europa.conf", "Conference League", "UECL", "128A4B", region: "Europe"),
        L(.football, "soccer/eng.2", "Championship", "EFL", "1C2C5B", region: "England"),
        L(.football, "soccer/eng.fa", "FA Cup", "FA Cup", "1B3A6B", region: "England"),
        L(.football, "soccer/esp.2", "LaLiga 2", "LaLiga 2", "1B2A57", region: "Spain"),
        L(.football, "soccer/ned.1", "Eredivisie", "ERE", "E8571B", region: "Netherlands"),
        L(.football, "soccer/por.1", "Primeira Liga", "Liga PT", "0C3C78", region: "Portugal"),
        L(.football, "soccer/sco.1", "Scottish Premiership", "SPFL", "2B0A57", region: "Scotland"),
        L(.football, "soccer/tur.1", "Süper Lig", "SL", "C8102E", region: "Türkiye"),
        L(.football, "soccer/swe.1", "Allsvenskan", "Allsv.", "0B4EA2", region: "Sweden"),
        L(.football, "soccer/ksa.1", "Saudi Pro League", "SPL", "1E5631", region: "Saudi Arabia"),
        L(.football, "soccer/usa.1", "MLS", "MLS", "0B1E3F", region: "USA"),
        L(.football, "soccer/mex.1", "Liga MX", "Liga MX", "0A3D2E", region: "Mexico"),
        L(.football, "soccer/bra.1", "Brasileirão", "BRA", "1F7A3A", region: "Brazil"),
        L(.football, "soccer/arg.1", "Liga Profesional", "ARG", "3D7EBF", region: "Argentina"),
        L(.football, "soccer/conmebol.libertadores", "Copa Libertadores", "Lib.", "8C6A12", region: "South America"),
        L(.football, "soccer/eng.w.1", "Women's Super League", "WSL", "4B1F7A", region: "England"),
        L(.football, "soccer/usa.nwsl", "NWSL", "NWSL", "0E2F5A", region: "USA"),
        L(.football, "soccer/fifa.world", "FIFA World Cup", "WC", "7A1230", region: "World"),
        // Basketball
        L(.basketball, "basketball/nba", "NBA", "NBA", "1D428A", playoffs: [4, 5, 6]),
        L(.basketball, "basketball/wnba", "WNBA", "WNBA", "E2601B", playoffs: [9, 10]),
        L(.basketball, "basketball/mens-college-basketball", "NCAA Men's", "NCAAM", "0E3A8A", playoffs: [3, 4]),
        L(.basketball, "basketball/womens-college-basketball", "NCAA Women's", "NCAAW", "6D28D9", playoffs: [3, 4]),
        // American football
        L(.americanFootball, "football/nfl", "NFL", "NFL", "013369", playoffs: [1, 2]),
        L(.americanFootball, "football/college-football", "College Football", "NCAAF", "7F1D1D"),
        // Baseball
        L(.baseball, "baseball/mlb", "MLB", "MLB", "0A2351", playoffs: [9, 10, 11]),
        L(.baseball, "baseball/college-baseball", "College Baseball", "NCAA", "2F5233"),
        // Hockey
        L(.hockey, "hockey/nhl", "NHL", "NHL", "1A1A1A", playoffs: [4, 5, 6]),
        L(.hockey, "hockey/mens-college-hockey", "NCAA Hockey", "NCAA", "274060"),
        // Rugby
        L(.rugby, "rugby/180659", "Six Nations", "6N", "0C2340", region: "Europe"),
        L(.rugby, "rugby/267979", "Premiership Rugby", "Prem", "5B1F6B", region: "England"),
        L(.rugby, "rugby/270557", "United Rugby Championship", "URC", "1B365D", region: "Europe"),
        L(.rugby, "rugby/164205", "Rugby World Cup", "RWC", "0B3B2E", region: "World"),
        // Motorsport
        L(.motorsport, "racing/f1", "Formula 1", "F1", "C80000", kind: .racing),
        L(.motorsport, "racing/nascar-premier", "NASCAR Cup Series", "NASCAR", "0F3A73", kind: .racing),
        L(.motorsport, "racing/irl", "IndyCar", "IndyCar", "0A2240", kind: .racing),
        // Golf
        L(.golf, "golf/pga", "PGA Tour", "PGA", "0B2D5B", kind: .golf),
        L(.golf, "golf/eur", "DP World Tour", "DPWT", "0A1F44", kind: .golf),
        L(.golf, "golf/lpga", "LPGA Tour", "LPGA", "0E4C92", kind: .golf),
        L(.golf, "golf/liv", "LIV Golf", "LIV", "1A1A1A", kind: .golf),
        // Tennis
        L(.tennis, "tennis/atp", "ATP Tour", "ATP", "1C3F94", kind: .tennis),
        L(.tennis, "tennis/wta", "WTA Tour", "WTA", "6B2C91", kind: .tennis),
        // MMA
        L(.mma, "mma/ufc", "UFC", "UFC", "B00B0B", kind: .mma),
        // Cricket
        L(.cricket, "cricket", "Cricket", "Cricket", "0D5C3F", kind: .cricket),
        // Lacrosse
        L(.lacrosse, "lacrosse/pll", "Premier Lacrosse League", "PLL", "151515"),
    ]

    static func league(_ path: String) -> LeagueRef? { leagues.first { $0.path == path } }
}

/// Identifies a team inside a league.
struct TeamKey: Hashable, Codable, Sendable {
    let leaguePath: String
    let id: String
    var league: LeagueRef? { Catalog.league(leaguePath) }
}
