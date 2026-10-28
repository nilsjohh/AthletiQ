import SwiftUI

struct LeagueView: View {
    let path: String
    var body: some View {
        if let league = Catalog.league(path) {
            switch league.kind {
            case .team: TeamLeagueView(league: league)
            case .racing: RacingLeagueView(league: league)
            case .golf: GolfLeagueView(league: league)
            case .tennis: TennisLeagueView(league: league)
            case .mma: MMALeagueView(league: league)
            case .cricket: CricketView(league: league)
            }
        } else {
            EmptyNote(text: "Unknown competition")
        }
    }
}

/// Shared header for every competition page.
struct LeagueHero: View {
    let league: LeagueRef
    var subtitle: String?
    private var favorites: Favorites { Favorites.shared }

    var body: some View {
        Hero(color: Color(hex: league.colorHex), secondary: Color(hex: league.sport.primaryHex), pattern: league.sport.pattern, height: 190) {
            HStack(spacing: 22) {
                LeagueLogo(league: league, size: 66)
                    .frame(width: 96, height: 96)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.2)))
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: league.sport.symbol)
                        Text(league.sport.name.uppercased())
                    }
                    .font(.system(size: 11, weight: .heavy)).tracking(1).opacity(0.75)
                    Text(league.name).font(.system(size: 38, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    if let subtitle { Text(subtitle).font(.title3.weight(.medium)).opacity(0.8) }
                }
                Spacer()
                FavoriteButton(isOn: favorites.isFavorite(league: league.path)) { favorites.toggle(league: league.path) }
            }
        }
    }
}

// MARK: - Team leagues

enum LeagueTab: String, CaseIterable, Identifiable {
    case games = "Games", standings = "Standings", stats = "Stats", playoffs = "Playoffs", teams = "Teams"
    var id: String { rawValue }
}

@Observable @MainActor
final class TeamLeagueModel {
    let league: LeagueRef
    var games: [Game] = []
    var groups: [StandingsGroup] = []
    var season: String?
    var leaders: [LeaderCategory] = []
    var bracket: Bracket?
    var teams: [TeamInfo] = []
    var loaded = false
    var leadersLoaded = false
    var bracketLoaded = false

    init(league: LeagueRef) { self.league = league }
    var hasLive: Bool { games.contains { $0.state == .live } }

    func refresh() async {
        async let g = ESPN.leagueGames(league)
        async let s = ESPN.standings(league)
        let (games, _) = await g
        let (groups, season) = await s
        if !games.isEmpty || !loaded { withAnimation(AQ.snappy) { self.games = games } }
        if !groups.isEmpty { self.groups = groups; self.season = season }
        loaded = true
    }

    func loadTab(_ tab: LeagueTab) async {
        switch tab {
        case .stats where !leadersLoaded:
            leaders = await ESPN.leaders(league); leadersLoaded = true
        case .playoffs where !bracketLoaded:
            bracket = await ESPN.bracket(league); bracketLoaded = true
        case .teams where teams.isEmpty:
            teams = await ESPN.teams(league)
        default: break
        }
    }
}

struct TeamLeagueView: View {
    let league: LeagueRef
    @State private var model: TeamLeagueModel
    @State private var tab: LeagueTab = .games
    @State private var day: Date?

    init(league: LeagueRef, model: TeamLeagueModel? = nil, tab: LeagueTab = .games) {
        self.league = league
        _model = State(initialValue: model ?? TeamLeagueModel(league: league))
        _tab = State(initialValue: tab)
    }

    private var tabs: [LeagueTab] { LeagueTab.allCases.filter { $0 != .playoffs || league.hasBracket } }
    private var accent: Color { Color(hex: league.sport.accentHex) }

    var body: some View {
        Page {
            LeagueHero(league: league, subtitle: model.season.map { "\($0) season" }).appear(0)
            TabBar(tabs: tabs, selection: $tab, title: { $0.rawValue }, accent: accent)
                .frame(maxWidth: .infinity)
                .appear(1)
            Group {
                if !model.loaded {
                    LoadingState()
                } else {
                    switch tab {
                    case .games: gamesTab
                    case .standings: standingsTab
                    case .stats: statsTab
                    case .playoffs: playoffsTab
                    case .teams: teamsTab
                    }
                }
            }
            .id(tab)
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
        }
        .animation(AQ.spring, value: tab)
        .refreshing(id: league.path, every: { model.hasLive ? 30 : 300 }) {
            await model.refresh()
            if day == nil { day = defaultDay }
        }
        .task(id: tab) { await model.loadTab(tab) }
    }

    // Games

    private var days: [Date] { Array(Set(model.games.map { Calendar.current.startOfDay(for: $0.date) })).sorted() }
    private var defaultDay: Date? {
        let today = Calendar.current.startOfDay(for: Date())
        if model.hasLive { return today }
        return days.first(where: { $0 >= today }) ?? days.last
    }

    @ViewBuilder private var gamesTab: some View {
        if days.isEmpty {
            EmptyNote(text: "No games in the next few days")
        } else {
            DayStrip(days: days, selection: Binding(get: { day ?? defaultDay }, set: { day = $0 }),
                     liveDays: Set(model.games.filter { $0.state == .live }.map { Calendar.current.startOfDay(for: $0.date) }),
                     accent: accent)
            let selected = day ?? defaultDay ?? days[0]
            let list = model.games.filter { Calendar.current.isDate($0.date, inSameDayAs: selected) }
                .sorted { ($0.state == .live ? 0 : 1, $0.date) < ($1.state == .live ? 0 : 1, $1.date) }
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Fmt.day(selected), trailing: "\(list.count) \(list.count == 1 ? "game" : "games")")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, g in GameCard(game: g).appear(i) }
                }
            }
            .id(selected)
        }
    }

    @ViewBuilder private var standingsTab: some View {
        if model.groups.isEmpty {
            EmptyNote(text: "Standings aren't available right now", symbol: "list.number")
        } else {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(model.groups) { g in
                    StandingsTable(group: g, league: league, title: model.groups.count > 1 ? g.name : nil,
                                   highlightColor: Color(hex: league.colorHex))
                }
            }
        }
    }

    @ViewBuilder private var statsTab: some View {
        if !model.leadersLoaded {
            LoadingState(label: "Loading leaders")
        } else if model.leaders.isEmpty {
            EmptyNote(text: "Stats aren't available for this competition", symbol: "chart.bar")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18, alignment: .top)], spacing: 18) {
                ForEach(Array(model.leaders.enumerated()), id: \.element.id) { i, c in
                    LeaderCard(category: c, path: league.path, limit: league.isSoccer ? 10 : 5, accent: accent).appear(i)
                }
            }
        }
    }

    @ViewBuilder private var playoffsTab: some View {
        if !model.bracketLoaded {
            LoadingState(label: "Building bracket")
        } else if let b = model.bracket {
            BracketView(bracket: b, league: league)
        } else {
            EmptyNote(text: "No playoff games yet this season", symbol: "trophy")
        }
    }

    @ViewBuilder private var teamsTab: some View {
        if model.teams.isEmpty {
            LoadingState(label: "Loading teams")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(Array(model.teams.enumerated()), id: \.element.id) { i, t in
                    TeamTile(team: t, path: league.path).appear(i)
                }
            }
        }
    }
}

struct TeamTile: View {
    let team: TeamInfo
    let path: String
    private var router: Router { Router.shared }
    var body: some View {
        let c = Color.team(team.colorHex, alt: team.altColorHex)
        Button { router.team(team, path) } label: {
            HStack(spacing: 10) {
                TeamLogo(team: team, size: 34)
                Text(team.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(height: 62)
            .background(LinearGradient(colors: [c.opacity(0.55), c.mix(with: .black, by: 0.8)], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
        }
        .buttonStyle(PressableStyle(hoverScale: 1.03))
    }
}

struct DayStrip: View {
    let days: [Date]
    @Binding var selection: Date?
    var liveDays: Set<Date> = []
    var accent: Color = .white

    var body: some View {
        ScrollViewReader { proxy in
            HScroll {
                HStack(spacing: 8) {
                    ForEach(Snapshot.enabled ? Array(days.prefix(14)) : days, id: \.self) { d in chip(d).id(d) }
                }
                .padding(.vertical, 4).padding(.horizontal, 2)
            }
            .onAppear { if let s = selection { proxy.scrollTo(s, anchor: .center) } }
            .onChange(of: selection) { _, s in if let s { withAnimation(AQ.spring) { proxy.scrollTo(s, anchor: .center) } } }
        }
    }

    private func chip(_ d: Date) -> some View {
        let cal = Calendar.current
        let selected = selection.map { cal.isDate($0, inSameDayAs: d) } ?? false
        return Button { withAnimation(AQ.spring) { selection = d } } label: {
            VStack(spacing: 2) {
                Text(cal.isDateInToday(d) ? "TODAY" : d.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(selected ? .black.opacity(0.65) : AQ.tertiary)
                Text(d.formatted(.dateTime.day())).font(.system(size: 18, weight: .bold, design: .rounded))
                Text(d.formatted(.dateTime.month(.abbreviated))).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? .black.opacity(0.65) : AQ.tertiary)
            }
            .frame(width: 56, height: 66)
            .foregroundStyle(selected ? Color.black : Color.primary)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(AQ.fill)))
            .overlay(alignment: .topTrailing) {
                if liveDays.contains(d) { Circle().fill(AQ.live).frame(width: 8, height: 8).padding(6) }
            }
            .shadow(color: selected ? accent.opacity(0.4) : .clear, radius: 10)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.06, pressScale: 0.92))
    }
}
