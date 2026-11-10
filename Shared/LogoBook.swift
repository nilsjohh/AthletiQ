import Foundation

/// Team and league badges from TheSportsDB, matched ahead of time by Tools/build_logos.py
/// and bundled as sportsdb_logos.json. The app never calls TheSportsDB's API — it only loads images.
enum LogoBook {
    private struct Book: Decodable {
        let teams: [String: String]
        let leagues: [String: String]
    }

    private static let book: Book = {
        guard let url = Bundle.main.url(forResource: "sportsdb_logos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let b = try? JSONDecoder().decode(Book.self, from: data) else { return Book(teams: [:], leagues: [:]) }
        return b
    }()

    /// Key = ESPN logo folder (nba, wnba, soccer, nfl…) + team id, e.g. "soccer|359".
    static func key(for team: TeamInfo) -> String? {
        guard let s = team.logo?.absoluteString, let r = s.range(of: "/teamlogos/") else { return nil }
        let folder = s[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        return folder.isEmpty ? nil : "\(folder)|\(team.id)"
    }

    /// Badge for a team, sized for display (TheSportsDB serves /tiny, /small and /medium variants).
    static func team(_ team: TeamInfo?, size: CGFloat) -> URL? {
        guard let team, let k = key(for: team), let s = book.teams[k], !s.isEmpty else { return nil }
        return URL(string: s + variant(size))
    }

    static func league(_ path: String, size: CGFloat) -> URL? {
        guard let s = book.leagues[path], !s.isEmpty else { return nil }
        return URL(string: s + variant(size))
    }

    private static func variant(_ size: CGFloat) -> String {
        size <= 24 ? "/tiny" : (size <= 90 ? "/small" : "/medium")
    }
}
