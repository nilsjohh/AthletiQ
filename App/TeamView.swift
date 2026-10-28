import SwiftUI
import WidgetKit

enum TeamTab: String, CaseIterable, Identifiable {
    case overview = "Overview", matches = "Matches", standings = "Standings", players = "Players"
    var id: String { rawValue }
}

@Observable @MainActor
final class TeamModel {
    let key: TeamKey
    var feed: TeamFeed?
    var leaders: [LeaderCategory] = []
    var roster: [Player] = []
    var playersLoaded = false
    var loaded = false

    init(key: TeamKey) { self.key = key }

    func refresh() async {
        if let f = await TeamFeed.load(key) {
            let wasLive = feed?.live != nil
            withAnimation(AQ.snappy) { feed = f }
            if wasLive != (f.live != nil) { WidgetCenter.shared.reloadAllTimelines() }
        }
        loaded = true
    }

    func loadPlayers() async {
        guard !playersLoaded, let league = key.league else { return }
        if league.isSoccer {
            roster = await ESPN.roster(key)
        } else {
            async let l = ESPN.leaders(league, teamID: key.id)
            async let r = ESPN.roster(key)
            leaders = await l
            roster = await r
        }
        playersLoaded = true
    }

    /// Football: squad stat leaderboards built from the roster.
    var soccerBoards: [LeaderCategory] {
        let defs: [(String, String, String)] = [("totalGoals", "Goals", "soccerball"), ("goalAssists", "Assists", "arrow.turn.up.right"),
                                                ("appearances", "Appearances", "person.fill.checkmark"), ("shotsOnTarget", "Shots on Target", "scope"),
                                                ("saves", "Saves", "hand.raised.fill"), ("yellowCards", "Yellow Cards", "rectangle.portrait.fill")]
        return defs.compactMap { key, title, _ in
            let ranked = roster.filter { ($0.stats[key] ?? 0) > 0 }.sorted { ($0.stats[key] ?? 0) > ($1.stats[key] ?? 0) }
            guard !ranked.isEmpty else { return nil }
            return LeaderCategory(id: key, title: title, leaders: ranked.prefix(5).map {
                Leader(id: "\(key)-\($0.id)", name: $0.name, team: nil, value: String(Int($0.stats[key] ?? 0)),
                       detail: [$0.position, $0.jersey.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "), headshot: $0.headshot)
            })
        }
    }
}

/// Season numbers derived from results and the table row.
struct TeamInsights {
    let played, wins, draws, losses: Int
    let scored, conceded: Double
    let cleanSheets: Int
    let home: (w: Int, d: Int, l: Int)
    let away: (w: Int, d: Int, l: Int)
    let biggestWin: Game?
    let worstLoss: Game?
    let last10: [(Game, Outcome, Double)]   // margin

    init(feed: TeamFeed, teamID: String) {
        let res = feed.results
        var w = 0, d = 0, l = 0, cs = 0
        var hw = 0, hd = 0, hl = 0, aw = 0, ad = 0, al = 0
        var sc = 0.0, co = 0.0
        var best: (Game, Double)?, worst: (Game, Double)?
        var last: [(Game, Outcome, Double)] = []
        for g in res {
            guard let o = g.outcome(for: teamID), let me = g.side(of: teamID), let them = g.opponent(of: teamID) else { continue }
            let a = me.scoreValue ?? 0, b = them.scoreValue ?? 0
            sc += a; co += b
            if b == 0 { cs += 1 }
            switch o {
            case .win: w += 1; if me.isHome { hw += 1 } else { aw += 1 }
            case .draw: d += 1; if me.isHome { hd += 1 } else { ad += 1 }
            case .loss: l += 1; if me.isHome { hl += 1 } else { al += 1 }
            }
            let m = a - b
            if m > 0, m > (best?.1 ?? 0) { best = (g, m) }
            if m < 0, m < (worst?.1 ?? 0) { worst = (g, m) }
            if last.count < 10 { last.append((g, o, m)) }
        }
        let n = max(w + d + l, 1)
        played = w + d + l; wins = w; draws = d; losses = l
        scored = sc / Double(n); conceded = co / Double(n); cleanSheets = cs
        home = (hw, hd, hl); away = (aw, ad, al)
        biggestWin = best?.0; worstLoss = worst?.0
        last10 = last.reversed()
    }
}

struct TeamView: View {
    let key: TeamKey
    @State private var model: TeamModel
    @State private var tab: TeamTab = .overview
    private var favorites: Favorites { Favorites.shared }

    init(key: TeamKey, model: TeamModel? = nil, tab: TeamTab = .overview) {
        self.key = key
        _model = State(initialValue: model ?? TeamModel(key: key))
        _tab = State(initialValue: tab)
    }

    private var info: TeamInfo? { model.feed?.info }
    private var color: Color { Color.team(info?.colorHex, alt: info?.altColorHex, fallback: Color(hex: key.league?.colorHex ?? "3A3A3C")) }
    /// Second club colour, kept distinct from the first.
    private var color2: Color {
        let alt = Color.team(info?.altColorHex, fallback: color.mix(with: .white, by: 0.35))
        return info?.altColorHex == info?.colorHex ? color.mix(with: .white, by: 0.35) : alt
    }
    private var league: LeagueRef? { key.league }
    private var tableLeague: LeagueRef? { model.feed?.tableLeaguePath.flatMap(Catalog.league) ?? league }
    private var isSoccer: Bool { league?.isSoccer ?? false }

    var body: some View {
        Group {
            if Snapshot.enabled { content } else { ScrollView { content } }
        }
        .background(
            ZStack(alignment: .top) {
                AQ.bg
                LinearGradient(colors: [color.opacity(0.55), color2.opacity(0.18), color.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 900)
                if let p = league?.sport.pattern {
                    SportPattern(kind: p, color: color, opacity: 0.08, lineWidth: 1.5).frame(height: 600)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.6), value: info?.id)
            .ignoresSafeArea()
        )
        .tint(color)
        .animation(AQ.spring, value: tab)
        .refreshing(id: "\(key.leaguePath)|\(key.id)", every: { model.feed?.live != nil ? 25 : 300 }) { await model.refresh() }
        .task(id: tab) { if tab == .players || tab == .overview { await model.loadPlayers() } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            hero.appear(0)
            TabBar(tabs: TeamTab.allCases, selection: $tab, title: { $0.rawValue }, accent: color, selectedText: .white)
                .frame(maxWidth: .infinity).appear(1)
            Group {
                if !model.loaded {
                    SkeletonPage()
                } else if let feed = model.feed {
                    switch tab {
                    case .overview: overview(feed)
                    case .matches: matches(feed)
                    case .standings: standings(feed)
                    case .players: players
                    }
                } else {
                    EmptyNote(text: "Couldn't load this team right now", symbol: "wifi.exclamationmark")
                }
            }
            .id(tab)
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
            SiteFooter()
        }
        .padding(.horizontal, 30).padding(.vertical, 24)
        .frame(maxWidth: 1240)
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero

    private var hero: some View {
        Hero(color: color, secondary: color2, pattern: league?.sport.pattern, height: 260) {
            HStack(spacing: 28) {
                FloatingCrest(team: info, size: 130, glow: color2)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: league?.sport.symbol ?? "sportscourt").fontWeight(.light)
                        Text((tableLeague?.name ?? league?.name ?? "").uppercased())
                        ColourSwatches(primary: color, secondary: color2)
                    }
                    .font(.system(size: 11, weight: .heavy)).tracking(1).opacity(0.85)
                    Text(info?.name ?? " ").font(.system(size: 46, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 18) {
                        if let r = model.feed?.record, !r.isEmpty { stat(r, "Record") }
                        if let s = model.feed?.standingSummary { stat(s, "Standing") }
                        if let v = model.feed?.venue { stat(v, "Home ground") }
                    }
                    form
                }
                Spacer()
                if let info {
                    FavoriteButton(isOn: favorites.isFavorite(team: favKey)) { favorites.toggle(team: info, key: favKey) }
                }
            }
        }
    }

    private var favKey: TeamKey { TeamKey(leaguePath: model.feed?.tableLeaguePath ?? key.leaguePath, id: key.id) }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .bold)).lineLimit(1)
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).opacity(0.65)
        }
    }

    @ViewBuilder private var form: some View {
        if let results = model.feed?.results, !results.isEmpty {
            HStack(spacing: 5) {
                Text("FORM").font(.system(size: 9, weight: .heavy)).tracking(0.8).opacity(0.65).padding(.trailing, 3)
                ForEach(Array(results.prefix(5).reversed().enumerated()), id: \.element.id) { i, g in
                    if let o = g.outcome(for: key.id) { OutcomeBadge(outcome: o, size: 22).appear(i + 2) }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Overview

    @ViewBuilder private func overview(_ feed: TeamFeed) -> some View {
        let ins = TeamInsights(feed: feed, teamID: key.id)
        if let live = feed.live {
            VStack(alignment: .leading, spacing: 14) {
                ClubSectionTitle(title: "Live now", color: color)
                MatchSpotlight(game: live, teamID: key.id, color: color)
            }
        } else if let next = feed.upcoming.first {
            VStack(alignment: .leading, spacing: 14) {
                ClubSectionTitle(title: "Next up", color: color)
                MatchSpotlight(game: next, teamID: key.id, color: color).tilt()
            }
        }

        VStack(alignment: .leading, spacing: 14) {
            ClubSectionTitle(title: "Season", color: color)
            seasonTiles(feed, ins)
        }

        HStack(alignment: .top, spacing: 18) {
            FormChart(items: ins.last10, color: color, teamID: key.id).frame(maxWidth: .infinity)
            splits(ins).frame(width: 360)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
            GameListCard(title: "Last matches", games: Array(feed.results.prefix(5)), teamID: key.id, tint: color)
            GameListCard(title: "Coming up", games: Array(feed.upcoming.dropFirst(feed.live == nil ? 1 : 0).prefix(5)), teamID: key.id, tint: color2)
        }

        if ins.biggestWin != nil || ins.worstLoss != nil {
            HStack(spacing: 18) {
                if let g = ins.biggestWin { recordCard("Biggest win", g, symbol: "arrow.up.right", tint: AQ.win) }
                if let g = ins.worstLoss { recordCard("Heaviest defeat", g, symbol: "arrow.down.right", tint: AQ.loss) }
                clubCard(feed)
            }
        }

        if let table = feed.table, let tl = tableLeague {
            VStack(alignment: .leading, spacing: 14) {
                ClubSectionTitle(title: table.name.count < 40 ? table.name : tl.name, color: color, trailing: "Full table") { tab = .standings }
                StandingsTable(group: table, league: tl, highlight: key.id, highlightColor: color, compactWindow: 7)
            }
        }
        let boards = isSoccer ? model.soccerBoards : model.leaders
        if !boards.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ClubSectionTitle(title: "Top performers", color: color, trailing: "All players") { tab = .players }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)], spacing: 18) {
                    ForEach(Array(boards.prefix(3).enumerated()), id: \.element.id) { i, c in
                        LeaderCard(category: c, path: key.leaguePath, limit: 3, accent: color.mix(with: .white, by: 0.25), tint: i % 2 == 0 ? color : color2).appear(i)
                    }
                }
            }
        }
        Text("Updated \(Fmt.time(feed.updated)) · Data from ESPN").font(.caption).foregroundStyle(AQ.tertiary)
    }

    private func seasonTiles(_ feed: TeamFeed, _ ins: TeamInsights) -> some View {
        let row = feed.position
        func v(_ k: String) -> String? { row?.display[k].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        var tiles: [(String, String)] = []
        if let r = row { tiles.append(("Position", Fmt.ordinal(r.rank))) }
        tiles.append(("Played", v("gamesPlayed") ?? "\(ins.played)"))
        tiles.append(("Won", v("wins") ?? "\(ins.wins)"))
        if isSoccer || league?.sport == .rugby { tiles.append(("Drawn", v("ties") ?? "\(ins.draws)")) }
        tiles.append(("Lost", v("losses") ?? "\(ins.losses)"))
        if let p = v("points"), [.soccer, .rugby, .hockey].contains(tableLeague?.tableStyle ?? .basketball) { tiles.append(("Points", p)) }
        if let pct = v("winPercent") { tiles.append(("Win %", pct)) }
        tiles.append((isSoccer ? "Goals / game" : "Scored / game", String(format: "%.1f", ins.scored)))
        tiles.append((isSoccer ? "Conceded / game" : "Allowed / game", String(format: "%.1f", ins.conceded)))
        if isSoccer { tiles.append(("Clean sheets", "\(ins.cleanSheets)")) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                StatTile(label: t.0, value: t.1, color: i % 3 == 1 ? color2 : color).appear(i)
            }
        }
    }

    private func splits(_ ins: TeamInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Home & away").font(.headline)
            splitRow("Home", ins.home, symbol: "house")
            splitRow("Away", ins.away, symbol: "airplane")
            Divider().opacity(0.4)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", ins.scored)).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(color)
                    Text(isSoccer ? "Goals for / game" : "Points for / game").font(.system(size: 11)).foregroundStyle(AQ.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", ins.conceded)).font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text(isSoccer ? "Against / game" : "Allowed / game").font(.system(size: 11)).foregroundStyle(AQ.secondary)
                }
            }
        }
        .card(tint: color2)
    }

    private func splitRow(_ label: String, _ r: (w: Int, d: Int, l: Int), symbol: String) -> some View {
        let total = max(r.w + r.d + r.l, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(isSoccer ? "\(r.w)-\(r.d)-\(r.l)" : "\(r.w)-\(r.l)").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
            }
            SplitBar(parts: [(Double(r.w) / Double(total), color), (Double(r.d) / Double(total), AQ.draw), (Double(r.l) / Double(total), AQ.loss.opacity(0.8))])
        }
    }

    private func recordCard(_ title: String, _ g: Game, symbol: String, tint: Color) -> some View {
        let me = g.side(of: key.id), opp = g.opponent(of: key.id)
        return VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .heavy)).foregroundStyle(tint)
            HStack(spacing: 10) {
                TeamLogo(team: opp?.team, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(me?.isHome == true ? "vs" : "@") \(opp?.team.shortName ?? "")").font(.system(size: 14, weight: .semibold))
                    Text(Fmt.day(g.date)).font(.system(size: 11)).foregroundStyle(AQ.secondary)
                }
                Spacer()
                Text("\(me?.score ?? "")–\(opp?.score ?? "")").font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint)
    }

    private func clubCard(_ feed: TeamFeed) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Club", systemImage: "building.columns").font(.system(size: 12, weight: .heavy)).foregroundStyle(color)
            HStack(spacing: 10) {
                ColourSwatches(primary: color, secondary: color2, size: 18)
                Text(info?.abbreviation ?? "").font(.system(size: 18, weight: .heavy, design: .rounded))
                Spacer()
            }
            if let v = feed.venue { Label(v, systemImage: "mappin.and.ellipse").font(.system(size: 12)).foregroundStyle(AQ.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
    }

    // MARK: Other tabs

    @ViewBuilder private func matches(_ feed: TeamFeed) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
            GameListCard(title: "Results", games: Array(feed.results.prefix(20)), teamID: key.id, tint: color)
            GameListCard(title: "Fixtures", games: Array(([feed.live].compactMap { $0 } + feed.upcoming).prefix(20)), teamID: key.id, tint: color2)
        }
    }

    @ViewBuilder private func standings(_ feed: TeamFeed) -> some View {
        if let table = feed.table, let tl = tableLeague {
            StandingsTable(group: table, league: tl, title: table.name, highlight: key.id, highlightColor: color)
        } else {
            EmptyNote(text: "No standings for this team's competition", symbol: "list.number")
        }
    }

    @ViewBuilder private var players: some View {
        if !model.playersLoaded {
            SkeletonPage()
        } else {
            let boards = isSoccer ? model.soccerBoards : model.leaders
            if !boards.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ClubSectionTitle(title: "Season leaders", color: color)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)], spacing: 18) {
                        ForEach(Array(boards.enumerated()), id: \.element.id) { i, c in
                            LeaderCard(category: c, path: key.leaguePath, limit: 5, accent: color.mix(with: .white, by: 0.25), tint: i % 2 == 0 ? color : color2).appear(i)
                        }
                    }
                }
            }
            if !model.roster.isEmpty {
                let groups = Dictionary(grouping: model.roster) { $0.position ?? "Squad" }
                let order = groups.keys.sorted { positionRank($0) < positionRank($1) }
                ForEach(order, id: \.self) { pos in
                    VStack(alignment: .leading, spacing: 12) {
                        ClubSectionTitle(title: positionName(pos), color: color, trailing: "\(groups[pos]?.count ?? 0)")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ForEach(Array((groups[pos] ?? []).enumerated()), id: \.element.id) { i, p in
                                PlayerTile(player: p, color: color, isSoccer: isSoccer).appear(i)
                            }
                        }
                    }
                }
            }
            if boards.isEmpty && model.roster.isEmpty {
                EmptyNote(text: "No player data for this team", symbol: "person.3")
            }
        }
    }

    private func positionRank(_ p: String) -> Int {
        let order: [String: Int] = ["G": 0, "GK": 0, "D": 1, "M": 2, "F": 3, "PG": 0, "SG": 1, "SF": 2, "PF": 3, "C": 4, "QB": 0, "RB": 1, "WR": 2, "TE": 3]
        return order[p] ?? 9
    }
    private func positionName(_ p: String) -> String {
        let names: [String: String] = ["G": isSoccer ? "Goalkeepers" : "Guards", "D": "Defenders", "M": "Midfielders", "F": isSoccer ? "Forwards" : "Forwards",
         "C": "Centers", "PG": "Point Guards", "SG": "Shooting Guards", "SF": "Small Forwards", "PF": "Power Forwards"]
        return names[p] ?? p
    }
}

// MARK: - Club pieces

struct ClubSectionTitle: View {
    let title: String
    let color: Color
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    @State private var grow = Snapshot.enabled
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Capsule().fill(color.gradient).frame(width: 5, height: grow ? 22 : 4)
            SectionTitle(title, trailing: trailing, action: action)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { grow = true } }
    }
}

struct ColourSwatches: View {
    let primary: Color
    let secondary: Color
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: -size * 0.3) {
            Circle().fill(primary).frame(width: size, height: size).overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            Circle().fill(secondary).frame(width: size, height: size).overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
        }
    }
}

/// Crest that drops in and gently floats.
struct FloatingCrest: View {
    let team: TeamInfo?
    let size: CGFloat
    let glow: Color
    @State private var shown = Snapshot.enabled
    @State private var float = false
    var body: some View {
        TeamLogo(team: team, size: size)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
            .background(Circle().fill(glow.opacity(0.35)).blur(radius: 34).scaleEffect(float ? 1.08 : 0.92))
            .scaleEffect(shown ? 1 : 0.5)
            .rotationEffect(.degrees(shown ? 0 : -18))
            .offset(y: float ? -3 : 3)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { shown = true }
                guard !Snapshot.enabled else { return }
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { float = true }
            }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let color: Color
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CountUpText(text: value).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(color.mix(with: .primary, by: 0.15))
            Text(label.uppercased()).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(AQ.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(hovering ? 0.32 : 0.22), color.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
        .scaleEffect(hovering ? 1.04 : 1)
        .animation(AQ.spring, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Bars for the last 10 results: height = margin, colour = result.
struct FormChart: View {
    let items: [(Game, Outcome, Double)]
    let color: Color
    let teamID: String
    @State private var grow = Snapshot.enabled
    @State private var hover: String?

    var body: some View {
        let maxM = max(items.map { abs($0.2) }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last \(items.count) results").font(.headline)
                Spacer()
                if let h = hover, let it = items.first(where: { $0.0.id == h }) {
                    let opp = it.0.opponent(of: teamID)
                    Text("\(it.0.side(of: teamID)?.score ?? "")–\(opp?.score ?? "") \(it.0.side(of: teamID)?.isHome == true ? "vs" : "@") \(opp?.team.shortName ?? "")")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(AQ.secondary)
                        .transition(.opacity)
                }
            }
            GeometryReader { geo in
                let mid = geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(AQ.stroke).frame(height: 1).offset(y: mid)
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.0.id) { i, it in
                            let h = max(6, CGFloat(abs(it.2) / maxM) * (mid - 18))
                            let c = it.1 == .win ? color : (it.1 == .draw ? AQ.draw : AQ.loss)
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                    .frame(height: it.2 >= 0 ? mid - (grow ? h : 0) : mid)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(c.gradient)
                                    .frame(height: grow ? h : 0)
                                    .overlay(alignment: it.2 >= 0 ? .top : .bottom) {
                                        TeamLogo(team: it.0.opponent(of: teamID)?.team, size: 16)
                                            .offset(y: it.2 >= 0 ? -20 : 20)
                                            .opacity(grow ? 1 : 0)
                                    }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(hover == it.0.id ? 1.08 : 1)
                            .onHover { h in withAnimation(AQ.snappy) { hover = h ? it.0.id : (hover == it.0.id ? nil : hover) } }
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.05), value: grow)
                        }
                    }
                }
            }
            .frame(height: 170)
        }
        .card()
        .onAppear { grow = true }
    }
}

struct SplitBar: View {
    let parts: [(Double, Color)]
    @State private var grow = Snapshot.enabled
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    if p.0 > 0 {
                        Capsule().fill(p.1.gradient).frame(width: max(4, (geo.size.width - 6) * p.0 * (grow ? 1 : 0.02)))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.2)) { grow = true } }
    }
}

struct PlayerTile: View {
    let player: Player
    let color: Color
    var isSoccer = false
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.gradient)
                if player.headshot == nil, let j = player.jersey {
                    Text(j).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                } else {
                    RemoteImage([player.headshot], size: 44, circular: true, placeholder: "person")
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    if let j = player.jersey, player.headshot != nil { Text("#\(j)").monospacedDigit() }
                    if let p = player.position { Text(p) }
                    if let a = player.age { Text("· \(a) yrs") }
                }
                .font(.system(size: 11)).foregroundStyle(AQ.secondary)
            }
            Spacer(minLength: 0)
            if isSoccer, let g = player.stats["totalGoals"], g > 0 {
                Label("\(Int(g))", systemImage: "soccerball").font(.system(size: 11, weight: .bold)).foregroundStyle(color.mix(with: .primary, by: 0.2))
            }
            if let f = player.flag { CountryTag(url: f) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovering ? color.opacity(0.14) : AQ.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hovering ? color.opacity(0.5) : AQ.stroke))
        .scaleEffect(hovering ? 1.025 : 1)
        .animation(AQ.spring, value: hovering)
        .onHover { hovering = $0 }
    }
}
