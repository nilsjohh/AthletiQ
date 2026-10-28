import SwiftUI

@Observable @MainActor
final class GameModel {
    let path: String
    let id: String
    var detail: GameDetail?
    var loaded = false
    init(path: String, id: String) { self.path = path; self.id = id }
    func refresh() async {
        if let d = await ESPN.summary(path, id: id) { withAnimation(AQ.snappy) { detail = d } }
        loaded = true
    }
}

struct GameView: View {
    let path: String
    let id: String
    @State private var model: GameModel
    private var router: Router { Router.shared }

    init(path: String, id: String, model: GameModel? = nil) {
        self.path = path; self.id = id
        _model = State(initialValue: model ?? GameModel(path: path, id: id))
    }

    private var homeFirst: Bool { path.hasPrefix("soccer") || path.hasPrefix("rugby") }

    var body: some View {
        Page {
            if let d = model.detail {
                scoreboard(d).appear(0)
                if !d.periodLabels.isEmpty && !d.game.home.linescores.isEmpty { linescore(d).appear(1) }
                HStack(alignment: .top, spacing: 18) {
                    if !d.keyEvents.isEmpty { timeline(d).frame(maxWidth: .infinity).appear(2) }
                    if !d.teamStats.isEmpty { teamStats(d).frame(maxWidth: .infinity).appear(3) }
                }
                if !d.performers.isEmpty { performers(d).appear(4) }
            } else if model.loaded {
                EmptyNote(text: "Game details aren't available", symbol: "sportscourt")
            } else {
                LoadingState(label: "Loading game")
            }
        }
        .refreshing(id: "\(path)-\(id)", every: { model.detail?.game.state == .live ? 15 : 120 }) { await model.refresh() }
    }

    private func sides(_ d: GameDetail) -> (Side, Side) { homeFirst ? (d.game.home, d.game.away) : (d.game.away, d.game.home) }

    private func scoreboard(_ d: GameDetail) -> some View {
        let (l, r) = sides(d)
        let lc = Color.team(l.team.colorHex, alt: l.team.altColorHex)
        let rc = Color.team(r.team.colorHex, alt: r.team.altColorHex)
        return ZStack {
            LinearGradient(colors: [lc, lc.mix(with: .black, by: 0.6), rc.mix(with: .black, by: 0.6), rc], startPoint: .leading, endPoint: .trailing)
            if let s = Catalog.league(path)?.sport.pattern { SportPattern(kind: s, opacity: 0.1) }
            VStack(spacing: 14) {
                HStack {
                    Text(d.game.note ?? d.game.competition ?? "").font(.system(size: 12, weight: .heavy)).tracking(0.8).opacity(0.8)
                    Spacer()
                    if d.game.state == .live { LivePill(label: d.game.liveLabel) }
                }
                HStack {
                    side(l, d)
                    Spacer()
                    VStack(spacing: 6) {
                        if d.game.hasScore {
                            Text("\(l.score ?? "0")  –  \(r.score ?? "0")")
                                .font(.system(size: 66, weight: .heavy, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                                .shadow(color: .black.opacity(0.3), radius: 10)
                        } else {
                            Text(Fmt.time(d.game.date)).font(.system(size: 54, weight: .heavy, design: .rounded))
                        }
                        Text(d.game.state == .pre ? Fmt.day(d.game.date) : d.game.detail)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(d.game.state == .live ? AQ.live : .white.opacity(0.8))
                        if let s = d.game.seriesSummary { Text(s).font(.system(size: 12, weight: .semibold)).opacity(0.75) }
                    }
                    Spacer()
                    side(r, d)
                }
                if let v = d.game.venue {
                    Label(v, systemImage: "mappin.and.ellipse").font(.system(size: 12, weight: .medium)).opacity(0.7)
                }
            }
            .padding(28)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .foregroundStyle(.white)
    }

    private func side(_ s: Side, _ d: GameDetail) -> some View {
        VStack(spacing: 10) {
            TeamLogo(team: s.team, size: 96).shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            TeamLink(team: s.team, path: path, font: .system(size: 17, weight: .heavy), short: true)
            if let r = s.record { Text(r).font(.system(size: 12, weight: .semibold)).opacity(0.7) }
        }
        .frame(width: 220)
        .opacity(d.game.isLoser(s) ? 0.75 : 1)
    }

    private func linescore(_ d: GameDetail) -> some View {
        let (l, r) = sides(d)
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(d.periodLabels, id: \.self) { Text($0).frame(width: 40) }
                Text("T").frame(width: 46)
            }
            .font(.system(size: 11, weight: .heavy)).foregroundStyle(AQ.tertiary)
            ForEach([l, r], id: \.team.id) { s in
                HStack(spacing: 0) {
                    HStack(spacing: 8) { TeamLogo(team: s.team, size: 22); Text(s.team.abbreviation).font(.system(size: 14, weight: .bold)) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(d.periodLabels.enumerated()), id: \.offset) { i, _ in
                        Text(i < s.linescores.count ? s.linescores[i] : "–").frame(width: 40).monospacedDigit().foregroundStyle(AQ.secondary)
                    }
                    Text(s.score ?? "–").frame(width: 46).font(.system(size: 15, weight: .heavy)).monospacedDigit()
                }
                .font(.system(size: 14))
            }
        }
        .card()
    }

    private func timeline(_ d: GameDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(path.hasPrefix("soccer") ? "Key moments" : "Scoring").font(.headline).padding(.bottom, 12)
            ForEach(Array(d.keyEvents.enumerated()), id: \.element.id) { i, e in
                let isHome = e.teamID == d.game.home.team.id
                HStack(alignment: .top, spacing: 12) {
                    Text(e.clock).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(AQ.secondary)
                        .frame(width: 58, alignment: .leading)
                    ZStack {
                        Circle().fill(eventColor(e.type)).frame(width: 26, height: 26)
                        Image(systemName: eventSymbol(e.type)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.type).font(.system(size: 13, weight: .bold))
                        Text(e.text).font(.system(size: 12)).foregroundStyle(AQ.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    TeamLogo(team: isHome ? d.game.home.team : d.game.away.team, size: 20).opacity(e.teamID == nil ? 0 : 1)
                }
                .padding(.vertical, 8)
                .appear(i)
                if i < d.keyEvents.count - 1 { Divider().opacity(0.3).padding(.leading, 70) }
            }
        }
        .card()
    }

    private func eventColor(_ t: String) -> Color {
        let l = t.lowercased()
        if l.contains("red") { return AQ.loss }
        if l.contains("yellow") { return Color(hex: "FFCC00").opacity(0.9) }
        return AQ.win.opacity(0.85)
    }
    private func eventSymbol(_ t: String) -> String {
        let l = t.lowercased()
        if l.contains("card") { return "rectangle.portrait.fill" }
        if l.contains("goal") || l.contains("penalty") { return "soccerball" }
        if l.contains("touchdown") { return "football.fill" }
        if l.contains("home run") { return "baseball.fill" }
        return "plus"
    }

    private func teamStats(_ d: GameDetail) -> some View {
        let (l, r) = sides(d)
        let lc = Color.team(l.team.colorHex, alt: l.team.altColorHex)
        let rc = Color.team(r.team.colorHex, alt: r.team.altColorHex)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                TeamLogo(team: l.team, size: 22)
                Spacer()
                Text("Team stats").font(.headline)
                Spacer()
                TeamLogo(team: r.team, size: 22)
            }
            ForEach(Array(d.teamStats.enumerated()), id: \.element.id) { i, s in
                let lv = homeFirst ? s.home : s.away
                let rv = homeFirst ? s.away : s.home
                StatBar(label: s.label, left: lv, right: rv, leftColor: lc, rightColor: rc).appear(i)
            }
        }
        .card()
    }

    private func performers(_ d: GameDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Top performers")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                ForEach(Array(d.performers.enumerated()), id: \.element.id) { i, p in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(p.category).font(.system(size: 12, weight: .heavy)).tracking(0.6).foregroundStyle(AQ.secondary)
                        HStack {
                            performer(homeFirst ? p.home : p.away, team: homeFirst ? d.game.home.team : d.game.away.team)
                            Spacer()
                            performer(homeFirst ? p.away : p.home, team: homeFirst ? d.game.away.team : d.game.home.team)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                    .card(padding: 14)
                    .appear(i)
                }
            }
        }
    }

    @ViewBuilder private func performer(_ l: Leader?, team: TeamInfo) -> some View {
        if let l {
            HStack(spacing: 10) {
                RemoteImage([l.headshot], size: 40, circular: true, placeholder: "person.fill")
                    .background(Circle().fill(Color.team(team.colorHex, alt: team.altColorHex).opacity(0.4)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).environment(\.layoutDirection, .leftToRight)
                    Text(l.value).font(.system(size: 12, weight: .bold)).foregroundStyle(AQ.secondary).lineLimit(1).environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}

struct StatBar: View {
    let label: String
    let left: String
    let right: String
    let leftColor: Color
    let rightColor: Color
    @State private var grow = false

    private func num(_ s: String) -> Double {
        let cleaned = s.replacingOccurrences(of: "%", with: "")
        if let d = Double(cleaned) { return d }
        if let first = cleaned.split(separator: "-").first, let d = Double(first) { return d }
        return 0
    }

    var body: some View {
        let a = num(left), b = num(right)
        let total = max(a + b, 0.0001)
        VStack(spacing: 5) {
            HStack {
                Text(left).font(.system(size: 13, weight: .bold)).monospacedDigit()
                Spacer()
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(AQ.secondary)
                Spacer()
                Text(right).font(.system(size: 13, weight: .bold)).monospacedDigit()
            }
            GeometryReader { geo in
                HStack(spacing: 4) {
                    Capsule().fill(leftColor.gradient).frame(width: max(4, (geo.size.width - 4) * (grow ? a / total : 0.5)))
                    Capsule().fill(rightColor.gradient)
                }
            }
            .frame(height: 6)
            .opacity(a + b == 0 ? 0.3 : 1)
        }
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.15)) { grow = true } }
    }
}

// MARK: - Bracket

struct BracketPage: View {
    let path: String
    @State private var bracket: Bracket?
    @State private var loaded = false

    init(path: String, bracket: Bracket? = nil) {
        self.path = path
        _bracket = State(initialValue: bracket)
        _loaded = State(initialValue: bracket != nil)
    }

    var body: some View {
        let league = Catalog.league(path)
        Page {
            if let league {
                Hero(color: Color(hex: league.colorHex), secondary: Color(hex: "B8860B"), pattern: league.sport.pattern, height: 190) {
                    HStack(spacing: 20) {
                        Image(systemName: "trophy").font(.system(size: 46, weight: .light))
                            .frame(width: 92, height: 92)
                            .background(Circle().fill(.white.opacity(0.12)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                            .symbolEffect(.bounce, value: loaded)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POSTSEASON").font(.system(size: 11, weight: .heavy)).tracking(1.2).opacity(0.75)
                            Text(bracket?.title ?? "\(league.short) Playoffs").font(.system(size: 38, weight: .heavy))
                            if let f = bracket?.finalMatchup { Text("\(f.round) · \(f.summary)").font(.title3.weight(.medium)).opacity(0.85) }
                        }
                    }
                }
                .appear(0)
                if let bracket {
                    BracketView(bracket: bracket, league: league)
                } else if loaded {
                    EmptyNote(text: "No playoff games yet this season", symbol: "trophy")
                } else {
                    LoadingState(label: "Building bracket")
                }
            }
        }
        .refreshing(id: path, every: { 60 }) {
            if let l = Catalog.league(path) { bracket = await ESPN.bracket(l) }
            loaded = true
        }
    }
}

struct BracketView: View {
    let bracket: Bracket
    let league: LeagueRef

    var body: some View {
        HScroll {
            HStack(alignment: .center, spacing: 22) {
                ForEach(Array(bracket.rounds.enumerated()), id: \.element.id) { ri, round in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            if ri == bracket.rounds.count - 1 { Image(systemName: "trophy.fill").foregroundStyle(Color(hex: "FFD54F")) }
                            Text(round.name.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(AQ.secondary)
                        }
                        VStack(spacing: 14) {
                            ForEach(Array(round.matchups.enumerated()), id: \.element.id) { mi, m in
                                SeriesCard(matchup: m, league: league, isFinal: ri == bracket.rounds.count - 1)
                                    .appear(ri * 3 + mi)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(width: 250)
                    if ri < bracket.rounds.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(AQ.tertiary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct SeriesCard: View {
    let matchup: SeriesMatchup
    let league: LeagueRef
    var isFinal = false
    private var router: Router { Router.shared }

    var body: some View {
        Button {
            if let g = matchup.games.last(where: { $0.state != .pre }) ?? matchup.games.first {
                router.push(.game(path: league.path, id: g.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if matchup.round != "" {
                    Text(matchup.round).font(.system(size: 10, weight: .bold)).foregroundStyle(AQ.tertiary).lineLimit(1)
                }
                ForEach(Array(matchup.teams.enumerated()), id: \.element.id) { i, t in
                    let lost = matchup.winnerID != nil && matchup.winnerID != t.id
                    HStack(spacing: 8) {
                        TeamLogo(team: t, size: 24)
                        TeamLink(team: t, path: league.path, font: .system(size: 13.5, weight: matchup.winnerID == t.id ? .heavy : .semibold))
                        Spacer(minLength: 4)
                        Text("\(matchup.wins[i])").font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(matchup.winnerID == t.id ? AQ.gold : Color.primary)
                    }
                    .opacity(lost ? 0.45 : 1)
                }
                HStack(spacing: 6) {
                    if matchup.games.contains(where: { $0.state == .live }) { LivePill() }
                    Text(matchup.summary).font(.system(size: 11, weight: .semibold)).foregroundStyle(AQ.secondary).lineLimit(1)
                }
            }
            .card(padding: 12, radius: 16, tint: isFinal ? Color(hex: "D4A017") : nil)
            .overlay {
                if isFinal { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: "FFD54F").opacity(0.5), lineWidth: 1.2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hoverScale: 1.03))
    }
}
