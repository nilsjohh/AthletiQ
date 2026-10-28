import SwiftUI

@MainActor
final class LeagueLogoStore {
    static let shared = LeagueLogoStore()
    private var logos: [String: URL] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    func cached(_ path: String) -> URL? { logos[path] }
    func logo(_ league: LeagueRef) async -> URL? {
        if let l = logos[league.path] { return l }
        if let t = inflight[league.path] { return await t.value }
        let t = Task { await ESPN.leagueLogo(league) }
        inflight[league.path] = t
        let u = await t.value
        inflight[league.path] = nil
        if let u { logos[league.path] = u }
        return u
    }
}

struct LeagueLogo: View {
    let league: LeagueRef
    var size: CGFloat
    @State private var url: URL?
    init(league: LeagueRef, size: CGFloat) {
        self.league = league; self.size = size
        _url = State(initialValue: LeagueLogoStore.shared.cached(league.path))
    }
    var body: some View {
        Group {
            if let url {
                RemoteImage([url.absoluteString.contains("/500/") ? URL(string: url.absoluteString.replacingOccurrences(of: "/500/", with: "/500-dark/")) : nil, url], size: size)
            } else {
                Image(systemName: league.sport.symbol).font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size)
            }
        }
        .task(id: league.path) { if url == nil, league.kind != .cricket { url = await LeagueLogoStore.shared.logo(league) } }
    }
}

// MARK: - Home

enum BigEvent: Identifiable, Hashable {
    case playoffs(LeagueRef, Bracket)
    case fight(LeagueRef, FightCard)
    case race(LeagueRef, RaceWeekend)
    case golf(LeagueRef, GolfTournament, String)
    case tennis(LeagueRef, TennisTournament)

    var id: String {
        switch self {
        case .playoffs(let l, _): "po-\(l.path)"
        case .fight(_, let c): "f-\(c.id)"
        case .race(_, let r): "r-\(r.id)"
        case .golf(_, let g, _): "g-\(g.id)"
        case .tennis(_, let t): "t-\(t.id)"
        }
    }
}

@Observable @MainActor
final class HomeModel {
    var games: [Game] = []
    var events: [BigEvent] = []
    var favoriteFeeds: [String: TeamFeed] = [:]
    var loaded = false

    static let featured = ["soccer/eng.1", "soccer/esp.1", "soccer/uefa.champions", "soccer/ita.1", "soccer/ger.1",
                           "basketball/nba", "football/nfl", "hockey/nhl", "baseball/mlb"]

    func refresh(favorites: Favorites) async {
        let paths = Array(NSOrderedSet(array: favorites.leagues + Self.featured)) as! [String]
        let leagues = paths.compactMap(Catalog.league).filter { $0.kind == .team }
        async let gamesTask: [Game] = withTaskGroup(of: [Game].self) { g in
            for l in leagues { g.addTask { await ESPN.todaysGames(l) } }
            var out: [Game] = []
            for await x in g { out += x }
            return out
        }
        async let eventsTask = loadEvents()
        let favs = favorites.teams.map(\.key)
        async let feedsTask: [String: TeamFeed] = withTaskGroup(of: (String, TeamFeed?).self) { g in
            for k in favs { g.addTask { ("\(k.leaguePath)|\(k.id)", await TeamFeed.load(k, withTable: false)) } }
            var out: [String: TeamFeed] = [:]
            for await (k, f) in g { if let f { out[k] = f } }
            return out
        }
        let all = await gamesTask
        let now = Date()
        games = all.filter { $0.state == .live || Calendar.current.isDateInToday($0.date) || ($0.state == .post && now.timeIntervalSince($0.date) < 14 * 3600) }
            .sorted { (rank($0), $0.date) < (rank($1), $1.date) }
        events = await eventsTask
        favoriteFeeds = await feedsTask
        loaded = true
    }

    private func rank(_ g: Game) -> Int { g.state == .live ? 0 : (g.state == .pre ? 1 : 2) }

    private func loadEvents() async -> [BigEvent] {
        let month = Calendar.current.component(.month, from: Date())
        var out: [BigEvent] = []
        await withTaskGroup(of: [BigEvent].self) { g in
            for l in Catalog.leagues where l.playoffMonths.contains(month) {
                g.addTask { if let b = await ESPN.bracket(l), !b.rounds.isEmpty { return [.playoffs(l, b)] }; return [] }
            }
            if let ufc = Catalog.league("mma/ufc") {
                g.addTask {
                    let cards = await ESPN.fightCards(ufc)
                    let next = cards.first { $0.state != .post && $0.date > Date().addingTimeInterval(-12 * 3600) }
                    return next.map { [.fight(ufc, $0)] } ?? []
                }
            }
            if let f1 = Catalog.league("racing/f1") {
                g.addTask {
                    let races = await ESPN.raceSeason(f1)
                    let next = races.first { $0.state != .post } ?? races.last
                    return next.map { [.race(f1, $0)] } ?? []
                }
            }
            if let pga = Catalog.league("golf/pga") {
                g.addTask {
                    let t = await ESPN.tournaments(pga)
                    guard let e = t.current.first, let gt = e.golfTournament() else { return [] }
                    return [.golf(pga, gt, e.date ?? "")]
                }
            }
            if let atp = Catalog.league("tennis/atp") {
                g.addTask {
                    let t = await ESPN.tournaments(atp)
                    return t.current.compactMap { $0.tennisTournament() }.filter { $0.state != .post }.prefix(1).map { .tennis(atp, $0) }
                }
            }
            for await x in g { out += x }
        }
        func order(_ e: BigEvent) -> Int {
            switch e { case .playoffs: 0; case .fight: 1; case .race: 2; case .golf: 3; case .tennis: 4 }
        }
        return out.sorted { order($0) < order($1) }
    }
}

struct HomeView: View {
    @Binding var selection: SidebarItem?
    private var favorites: Favorites { Favorites.shared }
    private var router: Router { Router.shared }
    @State private var model: HomeModel

    init(selection: Binding<SidebarItem?>, model: HomeModel? = nil) {
        _selection = selection
        _model = State(initialValue: model ?? HomeModel())
    }

    var body: some View {
        Page {
            header.appear(0)

            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Sports")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 14)], spacing: 14) {
                    ForEach(Array(SportID.allCases.enumerated()), id: \.element) { i, s in
                        SportTile(sport: s) { router.push(.sport(s)) }.appear(i)
                    }
                }
            }

            if !favorites.teams.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Your Teams")
                    HScroll {
                        HStack(spacing: 14) {
                            ForEach(Array(favorites.teams.enumerated()), id: \.element.id) { i, t in
                                FavoriteTeamCard(fav: t, feed: model.favoriteFeeds[t.id]).appear(i)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            if !favorites.leagues.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Your Leagues")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                        ForEach(Array(favorites.leagues.compactMap(Catalog.league).enumerated()), id: \.element.id) { i, l in
                            LeagueTile(league: l).appear(i)
                        }
                    }
                }
            }

            if !model.events.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Big Events")
                    HScroll {
                        HStack(spacing: 16) {
                            ForEach(Array(model.events.enumerated()), id: \.element.id) { i, e in
                                BigEventCard(event: e).appear(i)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Live & Today", trailing: model.games.contains { $0.state == .live } ? "\(model.games.filter { $0.state == .live }.count) live" : nil)
                if !model.loaded {
                    LoadingState(label: "Gathering scores")
                } else if model.games.isEmpty {
                    EmptyNote(text: "No games today in your leagues")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(Array(model.games.prefix(24).enumerated()), id: \.element.id) { i, g in GameCard(game: g).appear(i) }
                    }
                }
            }

        }
        .refreshing(id: "home-\(favorites.teams.count)-\(favorites.leagues.count)",
                    every: { model.games.contains { $0.state == .live } ? 30 : 180 }) {
            await model.refresh(favorites: favorites)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Wordmark(size: 38)
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}

struct SportTile: View {
    let sport: SportID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hex: sport.primaryHex), Color(hex: sport.primaryHex).mix(with: .black, by: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                SportPattern(kind: sport.pattern, opacity: hovering ? 0.22 : 0.13, lineWidth: 1.5)
                    .scaleEffect(hovering ? 1.08 : 1)
                Image(systemName: sport.symbol)
                    .font(.system(size: 40, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(hovering ? -10 : 0))
                    .scaleEffect(hovering ? 1.12 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)
                    .symbolEffect(.bounce, value: hovering)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sport.name).font(.system(size: 16, weight: .bold))
                    Text("\(sport.leagues.count) \(sport.leagues.count == 1 ? "competition" : "competitions")")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(14)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(hovering ? 0.3 : 0.1)))
            .shadow(color: Color(hex: sport.primaryHex).opacity(hovering ? 0.55 : 0.2), radius: hovering ? 22 : 10, y: 8)
            .foregroundStyle(.white)
            .animation(AQ.spring, value: hovering)
            .onHover { hovering = $0 }
        }
        .buttonStyle(PressableStyle(hoverScale: 1.03, pressScale: 0.95))
        .tilt(7)
    }
}

struct FavoriteTeamCard: View {
    let fav: FavoriteTeam
    let feed: TeamFeed?
    private var router: Router { Router.shared }

    var body: some View {
        let color = Color.team(fav.colorHex)
        Button { router.push(.team(fav.key)) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RemoteImage([fav.logo], size: 34, placeholder: "shield.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fav.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(feed?.standingSummary ?? feed?.record ?? " ").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
                Divider().opacity(0.3)
                if let g = feed?.live ?? feed?.upcoming.first {
                    let opp = g.opponent(of: fav.key.id)
                    HStack(spacing: 8) {
                        TeamLogo(team: opp?.team, size: 20)
                        Text("\(g.side(of: fav.key.id)?.isHome == true ? "vs" : "@") \(opp?.team.shortName ?? "")")
                            .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if g.state == .live {
                            Text("\(g.side(of: fav.key.id)?.score ?? "0")–\(opp?.score ?? "0")").font(.system(size: 13, weight: .heavy, design: .rounded))
                            Circle().fill(AQ.live).frame(width: 7, height: 7)
                        } else {
                            Text("\(Fmt.shortDay(g.date)) \(Fmt.time(g.date))").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                } else if feed == nil {
                    Text("Loading…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("No upcoming games").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
            .background(LinearGradient(colors: [color.opacity(0.85), color.mix(with: .black, by: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14)))
            .shadow(color: color.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.025))
    }
}

struct BigEventCard: View {
    let event: BigEvent
    private var router: Router { Router.shared }

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [color, color.mix(with: .black, by: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                SportPattern(kind: sport.pattern, opacity: 0.14)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: icon).font(.system(size: 12, weight: .bold))
                        Text(kicker).font(.system(size: 11, weight: .heavy)).tracking(0.8)
                        if isLive { LivePill(label: "LIVE") }
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    detailView
                    Text(title).font(.system(size: 20, weight: .heavy)).lineLimit(2)
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                .padding(18)
            }
            .frame(width: 340, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.14)))
            .shadow(color: color.opacity(0.4), radius: 18, y: 8)
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.025))
        .tilt(6)
    }

    private var sport: SportID {
        switch event {
        case .playoffs(let l, _), .fight(let l, _), .race(let l, _), .golf(let l, _, _), .tennis(let l, _): l.sport
        }
    }
    private var color: Color {
        switch event {
        case .playoffs(let l, _), .fight(let l, _), .race(let l, _), .golf(let l, _, _), .tennis(let l, _): Color(hex: l.colorHex).mix(with: Color(hex: sport.primaryHex), by: 0.3)
        }
    }
    private var icon: String {
        switch event { case .playoffs: "trophy.fill"; case .fight: "figure.martial.arts"; case .race: "flag.checkered"; case .golf: "figure.golf"; case .tennis: "tennis.racket" }
    }
    private var kicker: String {
        switch event {
        case .playoffs(let l, _): "\(l.short) PLAYOFFS"
        case .fight: "UFC FIGHT NIGHT"
        case .race(let l, _): l.short.uppercased()
        case .golf(let l, _, _): l.short.uppercased()
        case .tennis(let l, _): l.short.uppercased()
        }
    }
    private var isLive: Bool {
        switch event {
        case .playoffs(_, let b): b.rounds.last?.matchups.contains { $0.games.contains { $0.state == .live } } ?? false
        case .fight(_, let c): c.state == .live
        case .race(_, let r): r.state == .live
        case .golf(_, let g, _): g.state == .live
        case .tennis(_, let t): t.state == .live
        }
    }
    private var title: String {
        switch event {
        case .playoffs(_, let b): b.finalMatchup?.round ?? b.title
        case .fight(_, let c): c.name
        case .race(_, let r): r.name
        case .golf(_, let g, _): g.name
        case .tennis(_, let t): t.name
        }
    }
    private var subtitle: String {
        switch event {
        case .playoffs(_, let b): b.finalMatchup?.summary ?? b.title
        case .fight(_, let c): "\(Fmt.day(c.date)) · \(c.venue ?? "")"
        case .race(_, let r): [r.circuit, Fmt.range(r.date, r.endDate)].compactMap { $0 }.joined(separator: " · ")
        case .golf(_, let g, _): g.players.first.map { "Leader: \($0.athlete.name) \($0.toPar)" } ?? Fmt.range(g.date, g.endDate)
        case .tennis(_, let t): Fmt.range(t.date, t.endDate)
        }
    }
    @ViewBuilder private var detailView: some View {
        switch event {
        case .playoffs(_, let b):
            if let m = b.finalMatchup {
                HStack(spacing: 10) {
                    ForEach(Array(m.teams.enumerated()), id: \.offset) { i, t in
                        HStack(spacing: 6) {
                            TeamLogo(team: t, size: 30)
                            Text("\(m.wins[i])").font(.system(size: 26, weight: .heavy, design: .rounded))
                        }
                        if i == 0 { Text("–").font(.title2.weight(.bold)).opacity(0.6) }
                    }
                }
            }
        case .fight(_, let c):
            if let main = c.fights.first {
                HStack(spacing: -10) {
                    ForEach(main.fighters, id: \.athlete.id) { f in
                        RemoteImage([f.athlete.photo("mma/ufc")], size: 54, circular: true, placeholder: "person.fill")
                            .background(Circle().fill(.black.opacity(0.3)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                    }
                }
            }
        default: EmptyView()
        }
    }

    private func open() {
        switch event {
        case .playoffs(let l, _): router.push(.bracket(l.path))
        case .fight(_, let c): router.push(.fightCard(c))
        case .race(let l, let r): router.push(.race(r, l.path))
        case .golf(let l, let g, let start): router.push(.golf(l.path, startDate: start, name: g.name))
        case .tennis(let l, let t): router.push(.tennis(t, l.path))
        }
    }
}

// MARK: - Sport

struct SportView: View {
    let sport: SportID
    private var router: Router { Router.shared }
    private var favorites: Favorites { Favorites.shared }

    var body: some View {
        if sport.leagues.count == 1, let only = sport.leagues.first {
            LeagueView(path: only.path)
        } else {
            Page {
                Hero(color: Color(hex: sport.primaryHex), pattern: sport.pattern, height: 200) {
                    HStack(spacing: 20) {
                        Image(systemName: sport.symbol)
                            .font(.system(size: 46, weight: .light))
                            .frame(width: 96, height: 96)
                            .background(Circle().fill(.white.opacity(0.14)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sport.name).font(.system(size: 42, weight: .heavy))
                            Text("\(sport.leagues.count) competitions").font(.title3.weight(.medium)).opacity(0.8)
                        }
                    }
                }
                .appear(0)

                if sport == .football {
                    let regions = Array(NSOrderedSet(array: sport.leagues.map(\.region))) as! [String]
                    ForEach(regions, id: \.self) { r in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(r).font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(AQ.secondary)
                            grid(sport.leagues.filter { $0.region == r })
                        }
                    }
                } else {
                    grid(sport.leagues)
                }
            }
        }
    }

    private func grid(_ leagues: [LeagueRef]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            ForEach(Array(leagues.enumerated()), id: \.element.id) { i, l in
                LeagueTile(league: l).appear(i)
            }
        }
    }
}

struct LeagueTile: View {
    let league: LeagueRef
    private var router: Router { Router.shared }
    private var favorites: Favorites { Favorites.shared }

    var body: some View {
        let color = Color(hex: league.colorHex)
        Button { router.push(.league(league.path)) } label: {
            HStack(spacing: 14) {
                LeagueLogo(league: league, size: 44)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(league.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(league.region.isEmpty ? league.sport.name : league.region).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 4)
                if favorites.isFavorite(league: league.path) {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(.yellow).transition(.scale.combined(with: .opacity))
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .background(LinearGradient(colors: [color.opacity(0.75), color.mix(with: .black, by: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.025))
    }
}
