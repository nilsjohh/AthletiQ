import SwiftUI

// MARK: - Motorsport

@Observable @MainActor
final class RacingModel {
    let league: LeagueRef
    var races: [RaceWeekend] = []
    var standings: [(String, [DriverStanding])] = []
    var loaded = false
    init(league: LeagueRef) { self.league = league }
    func refresh() async {
        async let r = ESPN.raceSeason(league)
        async let s = ESPN.driverStandings(league)
        races = await r
        standings = await s
        loaded = true
    }
    var next: RaceWeekend? { races.first { $0.state != .post } }
    var last: RaceWeekend? { races.last { $0.state == .post } }
}

enum RacingTab: String, CaseIterable, Identifiable { case races = "Races", standings = "Standings"; var id: String { rawValue } }

struct RacingLeagueView: View {
    let league: LeagueRef
    @State private var model: RacingModel
    @State private var tab: RacingTab = .races
    private var router: Router { Router.shared }

    init(league: LeagueRef, model: RacingModel? = nil) { self.league = league; _model = State(initialValue: model ?? RacingModel(league: league)) }

    var body: some View {
        Page {
            LeagueHero(league: league, subtitle: "\(Calendar.current.component(.year, from: Date())) season · \(model.races.count) rounds").appear(0)
            if !model.loaded {
                LoadingState()
            } else {
                HStack(alignment: .top, spacing: 18) {
                    if let n = model.next { raceFeature(n, label: n.state == .live ? "THIS WEEKEND" : "NEXT RACE") }
                    if let l = model.last { raceFeature(l, label: "LAST RACE") }
                }
                TabBar(tabs: RacingTab.allCases, selection: $tab, title: { $0.rawValue }, accent: Color(hex: league.sport.accentHex))
                    .frame(maxWidth: .infinity)
                Group {
                    switch tab {
                    case .races: calendar
                    case .standings: standingsView
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(AQ.spring, value: tab)
        .refreshing(id: league.path, every: { model.next?.state == .live ? 60 : 600 }) { await model.refresh() }
    }

    private func raceFeature(_ r: RaceWeekend, label: String) -> some View {
        Button { router.push(.race(r, league.path)) } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hex: league.colorHex), Color(hex: league.colorHex).mix(with: .black, by: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                SportPattern(kind: .track, opacity: 0.12)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(label).font(.system(size: 11, weight: .heavy)).tracking(1).opacity(0.8)
                        if r.state == .live { LivePill() }
                    }
                    Spacer()
                    Text(r.name).font(.system(size: 22, weight: .heavy)).lineLimit(2)
                    Text([r.circuit, r.location].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 12, weight: .medium)).opacity(0.8).lineLimit(1)
                    HStack {
                        Text(Fmt.range(r.date, r.endDate)).font(.system(size: 12, weight: .bold))
                        Spacer()
                        if r.state == .post, let w = r.mainSession?.results.first {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill").foregroundStyle(Color(hex: "FFD54F"))
                                CountryTag(url: w.athlete.flag)
                                Text(w.athlete.name).font(.system(size: 13, weight: .bold))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.015))
    }

    private var calendar: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.races.enumerated()), id: \.element.id) { i, r in
                Button { router.push(.race(r, league.path)) } label: {
                    HStack(spacing: 14) {
                        Text("R\(i + 1)").font(.system(size: 12, weight: .heavy)).monospacedDigit().foregroundStyle(AQ.tertiary).frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text([r.circuit, r.location].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(AQ.tertiary).lineLimit(1)
                        }
                        Spacer()
                        if r.state == .post, let w = r.mainSession?.results.first {
                            CountryTag(url: w.athlete.flag)
                            Text(w.athlete.shortName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(AQ.secondary)
                        } else if r.state == .live {
                            LivePill()
                        }
                        Text(Fmt.range(r.date, r.endDate)).font(.system(size: 12, weight: .medium)).foregroundStyle(AQ.secondary).frame(width: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 10)
                    .opacity(r.state == .post ? 0.75 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
                .appear(i)
            }
        }
        .card(padding: 8)
    }

    private var standingsView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)], spacing: 18) {
            ForEach(model.standings, id: \.0) { title, rows in
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).padding(.bottom, 8)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 12) {
                            Text("\(r.rank)").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(r.rank <= 3 ? podium(r.rank) : AQ.secondary).frame(width: 26, alignment: .leading)
                            if let f = r.flag { CountryTag(url: f) } else { RemoteImage([r.logo], size: 22, placeholder: "car.fill") }
                            Text(r.name).font(.system(size: 13.5, weight: r.rank == 1 ? .bold : .medium)).lineLimit(1)
                            Spacer()
                            Text(r.points).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        .padding(.vertical, 6).padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(r.rank == 1 ? Color(hex: "FFD54F").opacity(0.1) : .clear))
                        .appear(i)
                    }
                }
                .card()
            }
        }
    }
}

func podium(_ rank: Int) -> Color {
    switch rank { case 1: Color(hex: "FFD54F"); case 2: Color(hex: "D9D9D9"); default: Color(hex: "D7925B") }
}

struct RaceView: View {
    let race: RaceWeekend
    let path: String
    @State private var session: String = ""

    var body: some View {
        let league = Catalog.league(path)
        let current = race.sessions.first { $0.id == session } ?? race.mainSession
        Page {
            Hero(color: Color(hex: league?.colorHex ?? "C80000"), pattern: .track, height: 200) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                        Text(league?.name.uppercased() ?? "")
                        if race.state == .live { LivePill() }
                    }
                    .font(.system(size: 11, weight: .heavy)).tracking(1).opacity(0.85)
                    Text(race.name).font(.system(size: 36, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                    Text([race.circuit, race.location, Fmt.range(race.date, race.endDate)].compactMap { $0 }.joined(separator: " · "))
                        .font(.title3.weight(.medium)).opacity(0.8)
                }
            }
            .appear(0)

            if race.sessions.count > 1 {
                TabBar(tabs: race.sessions.map { SessionTab(id: $0.id, name: $0.name) },
                       selection: Binding(get: { SessionTab(id: current?.id ?? "", name: current?.name ?? "") },
                                          set: { session = $0.id }),
                       title: { $0.name }, accent: Color(hex: "FF6B6B"))
                    .frame(maxWidth: .infinity)
            }

            if let s = current {
                if s.results.isEmpty || s.state == .pre {
                    EmptyNote(text: "\(s.name) · \(Fmt.day(s.date)) at \(Fmt.time(s.date))", symbol: "clock")
                } else {
                    if s.results.count >= 3 { podiumView(s).id(s.id) }
                    VStack(spacing: 2) {
                        ForEach(Array(s.results.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 14) {
                                Text("\(r.position)").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                                    .foregroundStyle(r.position <= 3 ? podium(r.position) : AQ.secondary).frame(width: 30, alignment: .leading)
                                RemoteImage([r.athlete.photo(path)], size: 32, circular: true, placeholder: "person.fill")
                                    .background(Circle().fill(AQ.fill))
                                CountryTag(url: r.athlete.flag)
                                Text(r.athlete.name).font(.system(size: 14, weight: r.position == 1 ? .bold : .medium))
                                Spacer()
                            }
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .appear(i)
                        }
                    }
                    .card(padding: 8)
                    .id("list-\(s.id)")
                }
            }
        }
        .animation(AQ.spring, value: session)
    }

    private func podiumView(_ s: RaceSession) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach([1, 0, 2], id: \.self) { i in
                let r = s.results[i]
                VStack(spacing: 8) {
                    RemoteImage([r.athlete.photo(path)], size: i == 0 ? 96 : 76, circular: true, placeholder: "person.fill")
                        .background(Circle().fill(podium(r.position).opacity(0.25)))
                        .overlay(Circle().strokeBorder(podium(r.position), lineWidth: 2.5))
                        .shadow(color: podium(r.position).opacity(0.5), radius: 14)
                    HStack(spacing: 5) {
                        CountryTag(url: r.athlete.flag)
                        Text(r.athlete.shortName).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    }
                    Text("P\(r.position)").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(podium(r.position))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .frame(height: i == 0 ? 240 : 210, alignment: .bottom)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [podium(r.position).opacity(0.22), .clear], startPoint: .bottom, endPoint: .top)))
                .appear(i)
            }
        }
    }
}

struct SessionTab: Hashable, Identifiable { let id: String; let name: String }

// MARK: - Golf

@Observable @MainActor
final class GolfModel {
    let league: LeagueRef
    var current: [(GolfTournament, String)] = []
    var calendar: [RawCalendarEntry] = []
    var loaded = false
    init(league: LeagueRef) { self.league = league }
    func refresh() async {
        let t = await ESPN.tournaments(league)
        current = t.current.compactMap { e in e.golfTournament().map { ($0, e.date ?? "") } }
        calendar = t.calendar
        loaded = true
    }
}

struct GolfLeagueView: View {
    let league: LeagueRef
    @State private var model: GolfModel
    private var router: Router { Router.shared }
    init(league: LeagueRef) { self.league = league; _model = State(initialValue: GolfModel(league: league)) }

    var body: some View {
        Page {
            LeagueHero(league: league, subtitle: model.current.first.map { "Now: \($0.0.name)" }).appear(0)
            if !model.loaded {
                LoadingState()
            } else {
                ForEach(model.current, id: \.0.id) { t, _ in
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(t.name, trailing: t.state == .live ? "Live" : Fmt.range(t.date, t.endDate))
                        GolfLeaderboard(tournament: t, path: league.path, limit: 15)
                    }
                }
                if !model.calendar.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Season schedule")
                        VStack(spacing: 2) {
                            ForEach(Array(model.calendar.enumerated()), id: \.offset) { i, c in
                                let start = ESPNDate.parse(c.startDate)
                                let done = (ESPNDate.parse(c.endDate) ?? .distantFuture) < Date()
                                Button {
                                    if let s = c.startDate { router.push(.golf(league.path, startDate: s, name: c.label ?? "")) }
                                } label: {
                                    HStack {
                                        Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? AQ.win : AQ.tertiary)
                                        Text(c.label ?? "").font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        Spacer()
                                        if let start { Text(Fmt.range(start, ESPNDate.parse(c.endDate))).font(.system(size: 12)).foregroundStyle(AQ.secondary) }
                                    }
                                    .padding(.vertical, 9).padding(.horizontal, 10)
                                    .opacity(done ? 0.7 : 1)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(RowStyle())
                                .appear(i)
                            }
                        }
                        .card(padding: 8)
                    }
                }
            }
        }
        .refreshing(id: league.path, every: { model.current.contains { $0.0.state == .live } ? 60 : 600 }) { await model.refresh() }
    }
}

struct GolfLeaderboard: View {
    let tournament: GolfTournament
    let path: String
    var limit: Int? = nil

    var body: some View {
        let players = limit.map { Array(tournament.players.prefix($0)) } ?? tournament.players
        let rounds = tournament.players.map(\.rounds.count).max() ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("POS").frame(width: 50, alignment: .leading)
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(0..<rounds, id: \.self) { Text("R\($0 + 1)").frame(width: 40) }
                Text("TO PAR").frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .heavy)).foregroundStyle(AQ.tertiary).padding(.horizontal, 8).padding(.bottom, 8)
            ForEach(Array(players.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 0) {
                    Text(p.position).font(.system(size: 13, weight: .bold)).monospacedDigit().frame(width: 50, alignment: .leading)
                        .foregroundStyle(i == 0 && tournament.state != .pre ? Color(hex: "FFD54F") : AQ.secondary)
                    HStack(spacing: 10) {
                        RemoteImage([p.athlete.photo(path)], size: 30, circular: true, placeholder: "person.fill")
                            .background(Circle().fill(AQ.fill))
                        CountryTag(url: p.athlete.flag)
                        Text(p.athlete.name).font(.system(size: 13.5, weight: i == 0 ? .bold : .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(0..<rounds, id: \.self) { r in
                        Text(r < p.rounds.count ? p.rounds[r] : "–").font(.system(size: 12.5)).monospacedDigit().foregroundStyle(AQ.secondary).frame(width: 40)
                    }
                    Text(p.toPar).font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(p.toPar.hasPrefix("-") ? Color(hex: "FF6B6B") : .white)
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
                .appear(i)
                if i < players.count - 1 { Divider().opacity(0.3) }
            }
        }
        .card()
    }
}

struct GolfTournamentView: View {
    let path: String
    let startDate: String
    let name: String
    @State private var tournament: GolfTournament?
    @State private var loaded = false

    var body: some View {
        let league = Catalog.league(path)
        Page {
            Hero(color: Color(hex: league?.colorHex ?? "0B2D5B"), secondary: Color(hex: "2E7D32"), pattern: .golf, height: 190) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.golf"); Text(league?.name.uppercased() ?? "")
                        if tournament?.state == .live { LivePill() }
                    }
                    .font(.system(size: 11, weight: .heavy)).tracking(1).opacity(0.85)
                    Text(tournament?.name ?? name).font(.system(size: 36, weight: .heavy)).lineLimit(2)
                    if let t = tournament { Text("\(Fmt.range(t.date, t.endDate)) · \(t.detail)").font(.title3.weight(.medium)).opacity(0.8) }
                }
            }
            .appear(0)
            if let t = tournament {
                if t.players.isEmpty { EmptyNote(text: "Field not announced yet", symbol: "person.3") }
                else { GolfLeaderboard(tournament: t, path: path) }
            } else if loaded {
                EmptyNote(text: "Leaderboard isn't available", symbol: "list.number")
            } else {
                LoadingState(label: "Loading leaderboard")
            }
        }
        .refreshing(id: "\(path)-\(startDate)", every: { tournament?.state == .live ? 60 : 600 }) {
            if let l = Catalog.league(path) { tournament = await ESPN.tournament(l, startDate: startDate)?.golfTournament() }
            loaded = true
        }
    }
}

// MARK: - Tennis

struct TennisLeagueView: View {
    let league: LeagueRef
    @State private var tournaments: [TennisTournament] = []
    @State private var loaded = false
    private var router: Router { Router.shared }

    var body: some View {
        Page {
            LeagueHero(league: league, subtitle: tournaments.isEmpty ? nil : "\(tournaments.count) tournaments this week").appear(0)
            if !loaded {
                LoadingState()
            } else if tournaments.isEmpty {
                EmptyNote(text: "No tournaments in play right now", symbol: "tennis.racket")
            } else {
                ForEach(Array(tournaments.enumerated()), id: \.element.id) { i, t in
                    Button { router.push(.tennis(t, league.path)) } label: {
                        HStack(spacing: 18) {
                            Image(systemName: t.major ? "trophy.fill" : "tennis.racket")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(t.major ? Color(hex: "FFD54F") : Color(hex: league.sport.accentHex))
                                .frame(width: 64, height: 64)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AQ.fill))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.name).font(.system(size: 18, weight: .bold))
                                Text([t.venue, Fmt.range(t.date, t.endDate)].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(AQ.secondary)
                                let live = t.matches.filter { $0.state == .live }.count
                                if live > 0 { Text("\(live) matches live").font(.system(size: 12, weight: .bold)).foregroundStyle(AQ.live) }
                            }
                            Spacer()
                            if let finalM = t.matches.last(where: { $0.round.lowercased().contains("final") && !$0.round.lowercased().contains("semi") && !$0.round.lowercased().contains("quarter") && $0.state == .post }),
                               let w = finalM.players.first(where: { $0.winner == true }) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("CHAMPION").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(Color(hex: "FFD54F"))
                                    Text(w.athlete.name).font(.system(size: 13, weight: .bold))
                                }
                            }
                            Image(systemName: "chevron.right").foregroundStyle(AQ.tertiary)
                        }
                        .card(tint: Color(hex: league.colorHex))
                    }
                    .buttonStyle(PressableStyle(hoverScale: 1.01))
                    .appear(i + 1)
                }
            }
        }
        .refreshing(id: league.path, every: { 120 }) {
            tournaments = (await ESPN.tournaments(league)).current.compactMap { $0.tennisTournament() }
            loaded = true
        }
    }
}

struct TennisTournamentView: View {
    let tournament: TennisTournament
    let path: String
    @State private var draw: String = ""

    var body: some View {
        let league = Catalog.league(path)
        let draws = tournament.draws
        let selected = draws.contains(draw) ? draw : (draws.first ?? "")
        let matches = tournament.matches.filter { $0.draw == selected }
        let rounds = Array(NSOrderedSet(array: matches.sorted { $0.date > $1.date }.map(\.round))) as! [String]
        Page {
            Hero(color: Color(hex: league?.colorHex ?? "1C3F94"), secondary: Color(hex: "8DB600"), pattern: .tennis, height: 180) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { Image(systemName: "tennis.racket"); Text(league?.name.uppercased() ?? "") }
                        .font(.system(size: 11, weight: .heavy)).tracking(1).opacity(0.85)
                    Text(tournament.name).font(.system(size: 36, weight: .heavy))
                    Text([tournament.venue, Fmt.range(tournament.date, tournament.endDate)].compactMap { $0 }.joined(separator: " · "))
                        .font(.title3.weight(.medium)).opacity(0.8)
                }
            }
            .appear(0)
            if draws.count > 1 {
                TabBar(tabs: draws.map { SessionTab(id: $0, name: $0) },
                       selection: Binding(get: { SessionTab(id: selected, name: selected) }, set: { draw = $0.id }),
                       title: { $0.name }, accent: Color(hex: "E6FF5C"))
                    .frame(maxWidth: .infinity)
            }
            ForEach(rounds, id: \.self) { r in
                VStack(alignment: .leading, spacing: 12) {
                    Text(r.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(AQ.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(Array(matches.filter { $0.round == r }.enumerated()), id: \.element.id) { i, m in TennisMatchCard(match: m).appear(i) }
                    }
                }
                .id("\(selected)-\(r)")
            }
        }
        .animation(AQ.spring, value: draw)
    }
}

struct TennisMatchCard: View {
    let match: TennisMatch
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if match.state == .live { LivePill() } else {
                    Text(match.state == .post ? "Final" : "\(Fmt.shortDay(match.date)) · \(Fmt.time(match.date))")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(AQ.secondary)
                }
                Spacer()
            }
            ForEach(Array(match.players.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 8) {
                    CountryTag(url: p.athlete.flag)
                    Text(p.athlete.name).font(.system(size: 13.5, weight: p.winner == true ? .bold : .medium)).lineLimit(1)
                    if let s = p.seed, !s.isEmpty, s != "0" { Text("(\(s))").font(.system(size: 11)).foregroundStyle(AQ.tertiary) }
                    if p.winner == true { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(AQ.win) }
                    Spacer(minLength: 4)
                    ForEach(Array(p.sets.enumerated()), id: \.offset) { i, s in
                        Text(s).font(.system(size: 15, weight: i < p.setWins.count && p.setWins[i] ? .heavy : .regular, design: .rounded))
                            .monospacedDigit().frame(width: 20)
                            .foregroundStyle(i < p.setWins.count && p.setWins[i] ? Color.primary : AQ.tertiary)
                    }
                }
                .opacity(p.winner == false && match.state == .post ? 0.6 : 1)
            }
        }
        .card(padding: 14, radius: 16, tint: match.state == .live ? AQ.live : nil)
    }
}

// MARK: - MMA

struct MMALeagueView: View {
    let league: LeagueRef
    @State private var cards: [FightCard] = []
    @State private var loaded = false

    init(league: LeagueRef, cards: [FightCard] = []) {
        self.league = league
        _cards = State(initialValue: cards)
        _loaded = State(initialValue: !cards.isEmpty)
    }
    private var router: Router { Router.shared }

    private var upcoming: [FightCard] { cards.filter { $0.state != .post } }
    private var past: [FightCard] { cards.filter { $0.state == .post }.reversed() }

    var body: some View {
        Page {
            LeagueHero(league: league, subtitle: "\(upcoming.count) upcoming events").appear(0)
            if !loaded {
                LoadingState()
            } else {
                if let next = upcoming.first {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(next.state == .live ? "Live now" : "Next event")
                        FightCardHero(card: next, compact: true).onTapGesture { router.push(.fightCard(next)) }
                    }
                }
                cardList("Upcoming", Array(upcoming.dropFirst().prefix(8)))
                cardList("Recent results", Array(past.prefix(12)))
            }
        }
        .refreshing(id: league.path, every: { cards.contains { $0.state == .live } ? 60 : 900 }) {
            cards = await ESPN.fightCards(league); loaded = true
        }
    }

    @ViewBuilder private func cardList(_ title: String, _ list: [FightCard]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                        Button { router.push(.fightCard(c)) } label: { FightCardRow(card: c) }
                            .buttonStyle(PressableStyle()).appear(i)
                    }
                }
            }
        }
    }
}

struct FightCardRow: View {
    let card: FightCard
    var body: some View {
        let main = card.fights.first
        HStack(spacing: 12) {
            HStack(spacing: -12) {
                ForEach(main?.fighters ?? [], id: \.athlete.id) { f in
                    RemoteImage([f.athlete.photo("mma/ufc")], size: 46, circular: true, placeholder: "person.fill")
                        .background(Circle().fill(Color(hex: "2A0A0A")))
                        .overlay(Circle().strokeBorder(AQ.stroke))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text("\(Fmt.day(card.date)) · \(card.fights.count) fights").font(.system(size: 11.5)).foregroundStyle(AQ.secondary)
                if card.state == .post, let w = main?.fighters.first(where: { $0.winner == true }) {
                    Text("\(w.athlete.name) wins").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(hex: "FFD43B"))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(AQ.tertiary)
        }
        .card(padding: 14, radius: 18)
    }
}

struct FightCardHero: View {
    let card: FightCard
    var compact = false
    var body: some View {
        let main = card.fights.first
        ZStack {
            LinearGradient(colors: [Color(hex: "7A0A0A"), Color(hex: "1A0505")], startPoint: .top, endPoint: .bottom)
            SportPattern(kind: .octagon, color: Color(hex: "FFD43B"), opacity: 0.12, lineWidth: 2)
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text(card.name.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(1.2).foregroundStyle(Color(hex: "FFD43B"))
                    if card.state == .live { LivePill() }
                }
                if let main, main.fighters.count == 2 {
                    HStack(alignment: .center, spacing: 20) {
                        fighter(main.fighters[0], main: main)
                        VStack(spacing: 6) {
                            Text("VS").font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                            Text(main.weightClass.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(AQ.secondary)
                            if let r = main.rounds { Text("\(r) rounds").font(.system(size: 11)).foregroundStyle(AQ.tertiary) }
                            if main.state == .post { Text(resultLine(main)).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "FFD43B")) }
                        }
                        fighter(main.fighters[1], main: main)
                    }
                }
                Text("\(Fmt.day(card.date)) · \(Fmt.time(card.date))\(card.venue.map { " · \($0)" } ?? "")")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(AQ.secondary)
            }
            .padding(24)
        }
        .frame(height: compact ? 300 : 340)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(hex: "FFD43B").opacity(0.25)))
        .shadow(color: Color(hex: "B00B0B").opacity(0.4), radius: 26, y: 12)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private func fighter(_ f: Fighter, main: Fight) -> some View {
        VStack(spacing: 8) {
            RemoteImage([f.athlete.photo("mma/ufc")], size: compact ? 130 : 160, circular: true, placeholder: "person.fill")
                .background(Circle().fill(AQ.fill))
                .overlay(Circle().strokeBorder(f.winner == true ? Color(hex: "FFD43B") : .white.opacity(0.2), lineWidth: f.winner == true ? 3 : 1))
                .shadow(color: f.winner == true ? Color(hex: "FFD43B").opacity(0.5) : .clear, radius: 16)
            HStack(spacing: 6) {
                CountryTag(url: f.athlete.flag)
                Text(f.athlete.name).font(.system(size: 17, weight: .heavy)).lineLimit(1)
            }
            if let r = f.record { Text(r).font(.system(size: 12, weight: .semibold)).foregroundStyle(AQ.secondary) }
        }
        .frame(width: 240)
        .opacity(main.state == .post && f.winner == false ? 0.6 : 1)
    }
}

func resultLine(_ f: Fight) -> String {
    var parts: [String] = []
    if let r = f.round { parts.append("R\(r)") }
    if let c = f.clock, !c.isEmpty { parts.append(c) }
    return parts.isEmpty ? "Final" : parts.joined(separator: " · ")
}

struct FightCardView: View {
    let card: FightCard
    var body: some View {
        Page {
            FightCardHero(card: card).appear(0)
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Fight card", trailing: "\(card.fights.count) bouts")
                ForEach(Array(card.fights.enumerated()), id: \.element.id) { i, f in
                    FightRow(fight: f, isMain: i == 0, isCoMain: i == 1).appear(i + 1)
                }
            }
        }
    }
}

struct FightRow: View {
    let fight: Fight
    var isMain = false
    var isCoMain = false
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(isMain ? "MAIN EVENT" : (isCoMain ? "CO-MAIN EVENT" : fight.weightClass.uppercased()))
                    .font(.system(size: 10.5, weight: .heavy)).tracking(1)
                    .foregroundStyle(isMain || isCoMain ? Color(hex: "FFD43B") : AQ.tertiary)
                if isMain || isCoMain { Text("· \(fight.weightClass)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(AQ.tertiary) }
                Spacer()
                if fight.state == .live { LivePill(label: fight.round.map { "R\($0)" } ?? "LIVE") }
                else if fight.state == .post { Text(resultLine(fight)).font(.system(size: 11, weight: .bold)).foregroundStyle(AQ.secondary) }
                else { Text(Fmt.time(fight.date)).font(.system(size: 11, weight: .bold)).foregroundStyle(AQ.secondary) }
            }
            HStack(spacing: 12) {
                side(fight.fighters[0], alignment: .leading)
                Text("vs").font(.system(size: 12, weight: .heavy)).foregroundStyle(AQ.tertiary)
                side(fight.fighters[1], alignment: .trailing)
            }
        }
        .card(padding: 14, radius: 18, tint: isMain ? Color(hex: "B00B0B") : nil)
    }

    private func side(_ f: Fighter, alignment: HorizontalAlignment) -> some View {
        let lead = alignment == .leading
        return HStack(spacing: 10) {
            if !lead { Spacer(minLength: 0) }
            if lead { photo(f) }
            VStack(alignment: alignment, spacing: 2) {
                HStack(spacing: 5) {
                    if f.winner == true && lead { Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(Color(hex: "FFD43B")) }
                    Text(f.athlete.name).font(.system(size: 14, weight: f.winner == true ? .heavy : .semibold)).lineLimit(1)
                    if f.winner == true && !lead { Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(Color(hex: "FFD43B")) }
                }
                HStack(spacing: 5) {
                    CountryTag(url: f.athlete.flag)
                    Text(f.record ?? "").font(.system(size: 11)).foregroundStyle(AQ.secondary)
                }
            }
            if !lead { photo(f) }
            if lead { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
        .opacity(fight.state == .post && f.winner == false ? 0.55 : 1)
    }

    private func photo(_ f: Fighter) -> some View {
        RemoteImage([f.athlete.photo("mma/ufc")], size: 48, circular: true, placeholder: "person.fill")
            .background(Circle().fill(AQ.fill))
    }
}

// MARK: - Cricket

struct CricketView: View {
    let league: LeagueRef
    @State private var games: [Game] = []
    @State private var loaded = false

    var body: some View {
        let series = Array(NSOrderedSet(array: games.sorted { ($0.state == .live ? 0 : 1) < ($1.state == .live ? 0 : 1) }.compactMap(\.competition))) as! [String]
        Page {
            LeagueHero(league: league, subtitle: "\(games.filter { $0.state == .live }.count) live matches").appear(0)
            if !loaded {
                LoadingState()
            } else if games.isEmpty {
                EmptyNote(text: "No cricket on right now", symbol: "cricket.ball")
            } else {
                ForEach(series, id: \.self) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(s.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(1).foregroundStyle(AQ.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14, alignment: .top)], spacing: 14) {
                            ForEach(Array(games.filter { $0.competition == s }.enumerated()), id: \.element.id) { i, g in
                                CricketCard(game: g).appear(i)
                            }
                        }
                    }
                }
            }
        }
        .refreshing(id: "cricket", every: { 60 }) { games = await ESPN.cricketMatches(); loaded = true }
    }
}

struct CricketCard: View {
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if game.state == .live { LivePill() } else {
                    Text(game.state == .post ? "Result" : "\(Fmt.shortDay(game.date)) · \(Fmt.time(game.date))")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(AQ.secondary)
                }
                Spacer()
            }
            ForEach([game.home, game.away], id: \.team.id) { s in
                HStack(spacing: 10) {
                    TeamLogo(team: s.team, size: 26)
                    Text(s.team.name).font(.system(size: 14, weight: s.winner == true ? .bold : .medium)).lineLimit(1)
                    Spacer()
                    Text(s.score ?? "").font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1)
                }
            }
            if !game.detail.isEmpty {
                Text(game.detail).font(.system(size: 11.5, weight: .medium)).foregroundStyle(game.state == .live ? Color(hex: "6EE7B7") : AQ.secondary).lineLimit(2)
            }
        }
        .card(padding: 14, radius: 18, tint: game.state == .live ? Color(hex: "0D5C3F") : nil)
    }
}
