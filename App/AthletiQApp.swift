import SwiftUI
import WidgetKit

@main
struct AthletiQApp: App {
    var body: some Scene {
        WindowGroup("AthletiQ") {
            RootView()
                .frame(minWidth: 1040, minHeight: 700)
                .onAppear { WidgetCenter.shared.reloadAllTimelines() }
        }
        .defaultSize(width: 1320, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

// MARK: - Navigation

enum Route: Hashable {
    case sport(SportID)
    case league(String)
    case team(TeamKey)
    case game(path: String, id: String)
    case bracket(String)
    case fightCard(FightCard)
    case race(RaceWeekend, String)
    case golf(String, startDate: String, name: String)
    case tennis(TennisTournament, String)
}

@Observable @MainActor
final class Router {
    static let shared = Router()
    var path: [Route] = []
    func push(_ r: Route) { withAnimation(AQ.snappy) { path.append(r) } }
    func team(_ team: TeamInfo, _ leaguePath: String?) {
        guard let leaguePath else { return }
        push(.team(TeamKey(leaguePath: leaguePath, id: team.id)))
    }
}

enum SidebarItem: Hashable {
    case home
    case sport(SportID)
    case league(String)
    case team(TeamKey)
}

// MARK: - Favourites

struct FavoriteTeam: Codable, Hashable, Identifiable {
    let key: TeamKey
    let name: String
    let logo: URL?
    let colorHex: String?
    var id: String { "\(key.leaguePath)|\(key.id)" }
}

@Observable @MainActor
final class Favorites {
    static let shared = Favorites()
    private(set) var teams: [FavoriteTeam] = []
    private(set) var leagues: [String] = []

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "fav.teams"), let t = try? JSONDecoder().decode([FavoriteTeam].self, from: data) { teams = t }
        leagues = d.stringArray(forKey: "fav.leagues") ?? []
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(teams), forKey: "fav.teams")
        d.set(leagues, forKey: "fav.leagues")
    }

    func isFavorite(team key: TeamKey) -> Bool { teams.contains { $0.key.id == key.id && $0.key.leaguePath.split(separator: "/").first == key.leaguePath.split(separator: "/").first } }
    func isFavorite(league path: String) -> Bool { leagues.contains(path) }

    func toggle(team info: TeamInfo, key: TeamKey) {
        if isFavorite(team: key) {
            teams.removeAll { $0.key.id == key.id && $0.key.leaguePath.split(separator: "/").first == key.leaguePath.split(separator: "/").first }
        } else {
            teams.append(FavoriteTeam(key: key, name: info.name, logo: info.darkLogo ?? info.logo, colorHex: info.colorHex))
        }
        save()
    }

    func toggle(league path: String) {
        if let i = leagues.firstIndex(of: path) { leagues.remove(at: i) } else { leagues.append(path) }
        save()
    }
}

// MARK: - Root

struct RootView: View {
    @Bindable private var router = Router.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView(selection: .constant(.home))
                .navigationDestination(for: Route.self) { destination($0) }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if !router.path.isEmpty {
                    Button {
                        withAnimation(AQ.spring) { router.path.removeAll() }
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    .help("Back to Home")
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(AQ.spring, value: router.path.isEmpty)
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .sport(let s): SportView(sport: s)
        case .league(let p): LeagueView(path: p)
        case .team(let k): TeamView(key: k)
        case .game(let p, let id): GameView(path: p, id: id)
        case .bracket(let p): BracketPage(path: p)
        case .fightCard(let c): FightCardView(card: c)
        case .race(let r, let p): RaceView(race: r, path: p)
        case .golf(let p, let start, let name): GolfTournamentView(path: p, startDate: start, name: name)
        case .tennis(let t, let p): TennisTournamentView(tournament: t, path: p)
        }
    }
}

struct Wordmark: View {
    var size: CGFloat = 18
    var body: some View {
        HStack(spacing: size * 0.45) {
            AppMark(size: size * 1.45)
            Text("AthletiQ")
                .font(.system(size: size, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.primary)
        }
    }
}

/// The app mark: a black rounded square with a single white "Q" ring.
struct AppMark: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "2A2A2D"), Color(hex: "0A0A0B")], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            QGlyph().fill(.white).frame(width: size * 0.56, height: size * 0.56)
        }
        .frame(width: size, height: size)
    }
}

/// A ring with a short diagonal tail.
struct QGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width
        let lw = w * 0.17
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: lw / 2, dy: lw / 2))
        let ring = p.strokedPath(StrokeStyle(lineWidth: lw))
        var tail = Path()
        tail.move(to: CGPoint(x: r.minX + w * 0.62, y: r.minY + w * 0.62))
        tail.addLine(to: CGPoint(x: r.minX + w * 0.98, y: r.minY + w * 0.98))
        return ring.union(tail.strokedPath(StrokeStyle(lineWidth: lw, lineCap: .round)))
    }
}
