import SwiftUI

/// A team name that opens the team page.
struct TeamLink: View {
    let team: TeamInfo
    let path: String?
    var font: Font = .system(size: 14, weight: .semibold)
    var short = true
    private var router: Router { Router.shared }

    var body: some View {
        Button { router.team(team, linkPath) } label: {
            Text(short ? team.shortName : team.name).font(font).lineLimit(1)
        }
        .buttonStyle(LinkStyle())
        .disabled(linkPath == nil)
    }

    /// Cup and cross-league games link to the team's page via the catalogue league when possible.
    private var linkPath: String? {
        guard let path else { return nil }
        if Catalog.league(path) != nil { return path }
        if path.hasPrefix("soccer/") { return "soccer/eng.1" }
        return nil
    }
}

// MARK: - Scoreboard card

struct GameCard: View {
    let game: Game
    var highlight: String? = nil
    @State private var flash = false
    private var router: Router { Router.shared }

    private var soccerStyle: Bool { (game.leaguePath ?? "").hasPrefix("soccer") || (game.leaguePath ?? "").hasPrefix("rugby") || game.leaguePath == "cricket" }
    private var rows: [Side] { soccerStyle ? [game.home, game.away] : [game.away, game.home] }
    private var accent: Color { Color.team(game.home.team.colorHex, alt: game.home.team.altColorHex) }

    var body: some View {
        Button {
            if let p = game.leaguePath, p != "cricket" { router.push(.game(path: p, id: game.id)) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    status
                    Spacer(minLength: 4)
                    Text(game.note ?? game.competition ?? "")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(AQ.tertiary).lineLimit(1)
                }
                VStack(spacing: 10) {
                    ForEach(rows, id: \.team.id) { teamRow($0) }
                }
                if let s = game.seriesSummary, !s.isEmpty {
                    Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(AQ.secondary)
                } else if let v = game.venue {
                    Text(v).font(.system(size: 11)).foregroundStyle(AQ.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14, radius: 18, tint: game.state == .live ? AQ.live : nil)
            .overlay(alignment: .topLeading) {
                if game.state == .live {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AQ.live.opacity(0.45), lineWidth: 1.2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(flash ? 0.9 : 0), lineWidth: 2)
                    .shadow(color: .yellow.opacity(flash ? 0.6 : 0), radius: 12)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressableStyle())
        .onChange(of: "\(game.home.score ?? "")-\(game.away.score ?? "")") { old, new in
            guard old != "-", old != new, game.state == .live else { return }
            withAnimation(.easeIn(duration: 0.15)) { flash = true }
            withAnimation(.easeOut(duration: 1.2).delay(0.6)) { flash = false }
        }
    }

    @ViewBuilder private var status: some View {
        switch game.state {
        case .live: LivePill(label: game.liveLabel)
        case .post:
            Text(game.completed ? (game.shortDetail.isEmpty ? "Final" : game.shortDetail) : game.detail)
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(AQ.secondary).lineLimit(1)
        case .pre:
            Text(Calendar.current.isDateInToday(game.date) ? Fmt.time(game.date) : "\(Fmt.shortDay(game.date)) · \(Fmt.time(game.date))")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(AQ.secondary)
        }
    }

    private func teamRow(_ side: Side) -> some View {
        let loser = game.isLoser(side)
        return HStack(spacing: 10) {
            TeamLogo(team: side.team, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                TeamLink(team: side.team, path: game.leaguePath,
                         font: .system(size: 14, weight: side.team.id == highlight ? .heavy : .semibold))
                if let r = side.record, !soccerStyle, !r.isEmpty {
                    Text(r).font(.system(size: 10.5)).foregroundStyle(AQ.tertiary)
                }
            }
            Spacer(minLength: 6)
            if game.hasScore, let s = side.score {
                Text(s)
                    .font(.system(size: game.leaguePath == "cricket" ? 14 : 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                if side.winner == true && game.state == .post {
                    Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7)).foregroundStyle(AQ.secondary)
                }
            }
        }
        .opacity(loser ? 0.55 : 1)
    }
}

// MARK: - Team-centric list row

struct GameRow: View {
    let game: Game
    let teamID: String
    private var router: Router { Router.shared }

    var body: some View {
        let opp = game.opponent(of: teamID)
        let me = game.side(of: teamID)
        Button {
            if let p = game.leaguePath { router.push(.game(path: p, id: game.id)) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.day(game.date)).font(.system(size: 13, weight: .semibold))
                    Text(game.note ?? game.competition ?? "").font(.system(size: 11)).foregroundStyle(AQ.tertiary).lineLimit(1)
                }
                .frame(width: 140, alignment: .leading)
                TeamLogo(team: opp?.team, size: 26)
                HStack(spacing: 4) {
                    Text(me?.isHome == true ? "vs" : "@").font(.system(size: 12, weight: .medium)).foregroundStyle(AQ.tertiary)
                    if let o = opp { TeamLink(team: o.team, path: game.leaguePath, font: .system(size: 13.5, weight: .semibold)) }
                }
                Spacer(minLength: 6)
                switch game.state {
                case .post:
                    Text("\(me?.score ?? "–")–\(opp?.score ?? "–")")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    if let o = game.outcome(for: teamID) { OutcomeBadge(outcome: o, size: 22) }
                case .live:
                    Text("\(me?.score ?? "0")–\(opp?.score ?? "0")")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    LivePill(label: game.liveLabel)
                case .pre:
                    Text(Fmt.time(game.date)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(AQ.secondary)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
    }
}

/// Subtle row highlight on hover.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration) }
    private struct StyledBody: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : (hovering ? 0.045 : 0))))
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(AQ.snappy, value: hovering)
                .animation(AQ.snappy, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

struct GameListCard: View {
    let title: String
    let games: [Game]
    let teamID: String
    var tint: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).padding(.bottom, 8).padding(.horizontal, 10)
            if games.isEmpty {
                Text("Nothing scheduled").foregroundStyle(AQ.tertiary).padding(10)
            }
            ForEach(Array(games.enumerated()), id: \.element.id) { i, g in
                GameRow(game: g, teamID: teamID).appear(i)
                if i < games.count - 1 { Divider().opacity(0.4).padding(.horizontal, 10) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10, tint: tint)
    }
}

// MARK: - Spotlight (next / live match)

struct MatchSpotlight: View {
    let game: Game
    let teamID: String?
    let color: Color
    private var router: Router { Router.shared }

    var body: some View {
        Button {
            if let p = game.leaguePath { router.push(.game(path: p, id: game.id)) }
        } label: {
            VStack(spacing: 18) {
                HStack {
                    Text(game.note ?? game.competition ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(AQ.secondary)
                    Spacer()
                    if game.state == .live { LivePill(label: game.liveLabel) }
                    else { Text(Fmt.day(game.date)).font(.subheadline.weight(.semibold)).foregroundStyle(AQ.secondary) }
                }
                HStack(alignment: .center) {
                    column(left)
                    Spacer()
                    center
                    Spacer()
                    column(right)
                }
                if let v = game.venue {
                    Label(v, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(AQ.tertiary)
                }
            }
            .padding(24)
            .background(
                ZStack {
                    LinearGradient(colors: [Color.team(game.home.team.colorHex, alt: game.home.team.altColorHex).opacity(0.35), .clear, Color.team(game.away.team.colorHex, alt: game.away.team.altColorHex).opacity(0.35)],
                                   startPoint: .leading, endPoint: .trailing)
                    AQ.card
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(AQ.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(PressableStyle(hoverScale: 1.008))
    }

    /// Football lists home first; US sports list away first.
    private var homeFirst: Bool { (game.leaguePath ?? "").hasPrefix("soccer") || (game.leaguePath ?? "").hasPrefix("rugby") }
    private var left: Side { homeFirst ? game.home : game.away }
    private var right: Side { homeFirst ? game.away : game.home }

    @ViewBuilder private var center: some View {
        if game.hasScore {
            VStack(spacing: 4) {
                Text("\(left.score ?? "0")  –  \(right.score ?? "0")")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(game.state == .live ? game.detail : (game.seriesSummary ?? "Full time"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(game.state == .live ? AQ.live : AQ.secondary)
            }
        } else {
            VStack(spacing: 4) {
                Text(Fmt.time(game.date))
                    .font(.system(size: 50, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(game.date, format: .relative(presentation: .named))
                    .font(.callout.weight(.medium)).foregroundStyle(AQ.secondary)
            }
        }
    }

    private func column(_ side: Side) -> some View {
        VStack(spacing: 10) {
            TeamLogo(team: side.team, size: 82)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            TeamLink(team: side.team, path: game.leaguePath, font: .system(size: 15, weight: side.team.id == teamID ? .heavy : .semibold))
            Text(side.isHome ? "Home" : "Away").font(.caption).foregroundStyle(AQ.tertiary)
        }
        .frame(width: 190)
    }
}

// MARK: - Standings

struct StandingsTable: View {
    let group: StandingsGroup
    let league: LeagueRef
    var title: String? = nil
    var highlight: String? = nil
    var highlightColor: Color = .white
    var compactWindow: Int? = nil

    private var rows: [StandingRow] {
        if let n = compactWindow, let h = highlight { return group.window(around: h, count: n) }
        return group.rows
    }
    private var columns: [StandingColumn] { StandingColumn.visible(for: league.tableStyle, rows: group.rows) }

    private var legend: [(String, String)] {
        var seen = Set<String>()
        return group.rows.compactMap { r in
            guard let n = r.note, let c = r.noteColorHex, seen.insert(n).inserted else { return nil }
            return (n, c)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { Text(title).font(.headline).padding(.bottom, 12) }
            header
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                StandingRowView(row: row, columns: columns, league: league,
                                isHighlight: row.team.id == highlight, highlightColor: highlightColor)
                    .appear(i)
                if i < rows.count - 1 { Divider().opacity(0.35).padding(.leading, 42) }
            }
            if !legend.isEmpty && compactWindow == nil {
                HStack(spacing: 16) {
                    ForEach(legend, id: \.0) { item in
                        HStack(spacing: 6) {
                            Capsule().fill(Color(hex: item.1)).frame(width: 10, height: 4)
                            Text(item.0).font(.caption).foregroundStyle(AQ.secondary)
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
        .card(padding: 16)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 36, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { c in Text(c.label).frame(width: c.width, alignment: .trailing) }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(AQ.tertiary)
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}

struct StandingRowView: View {
    let row: StandingRow
    let columns: [StandingColumn]
    let league: LeagueRef
    let isHighlight: Bool
    let highlightColor: Color
    private var router: Router { Router.shared }

    var body: some View {
        Button { router.team(row.team, league.path) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Capsule().fill(row.noteColorHex.map { Color(hex: $0) } ?? .clear).frame(width: 3, height: 18)
                    Text("\(row.rank)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(AQ.secondary)
                }
                .frame(width: 36, alignment: .leading)
                HStack(spacing: 10) {
                    TeamLogo(team: row.team, size: 22)
                    Text(row.team.name).font(.system(size: 13.5, weight: isHighlight ? .heavy : .medium)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns) { c in
                    Text(c.format(row.value(c.key)))
                        .font(.system(size: 13, weight: c.emphasized ? .bold : .regular)).monospacedDigit()
                        .foregroundStyle(c.emphasized ? Color.primary : AQ.secondary)
                        .frame(width: c.width, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHighlight ? highlightColor.opacity(0.22) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
    }
}

// MARK: - Leaders

struct LeaderCard: View {
    let category: LeaderCategory
    var path: String?
    var limit = 5
    var accent: Color = .primary
    var tint: Color? = nil
    private var router: Router { Router.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title).font(.headline)
            ForEach(Array(category.leaders.prefix(limit).enumerated()), id: \.element.id) { i, leader in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(AQ.tertiary)
                        .frame(width: 16, alignment: .leading)
                    if let h = leader.headshot {
                        RemoteImage([h], size: i == 0 ? 40 : 32, circular: true, placeholder: "person.fill")
                            .background(Circle().fill(AQ.fill))
                    } else if let t = leader.team {
                        TeamLogo(team: t, size: 26).frame(width: 32)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.45))
                            .frame(width: i == 0 ? 40 : 32, height: i == 0 ? 40 : 32)
                            .background(Circle().fill(accent.opacity(0.18)))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(leader.name).font(.system(size: 13, weight: i == 0 ? .bold : .medium)).lineLimit(1)
                        HStack(spacing: 4) {
                            if let t = leader.team {
                                Button { router.team(t, path) } label: { Text(t.abbreviation) }.buttonStyle(LinkStyle())
                            }
                            if let d = leader.detail, !d.isEmpty { Text(leader.team == nil ? d : "· \(d)") }
                        }
                        .font(.caption).foregroundStyle(AQ.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(leader.value)
                        .font(.system(size: i == 0 ? 22 : 15, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(i == 0 ? accent : Color.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, tint: tint)
    }
}
