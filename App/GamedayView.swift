import SwiftUI

/// Matchday banner for a favourite team: full width, compact height.
/// Before, during and just after the game; the match centre has the full detail.
struct GamedayCard: View {
    let day: Gameday
    private var router: Router { Router.shared }
    @State private var pulse = false

    private var game: Game { day.detail?.game ?? day.game }
    private var favID: String { day.fav.key.id }
    private var me: Side? { game.side(of: favID) }
    private var opp: Side? { game.opponent(of: favID) }
    private var color: Color { Color.team(me?.team.colorHex ?? day.fav.colorHex, alt: me?.team.altColorHex) }
    private var oppColor: Color { Color.team(opp?.team.colorHex, alt: opp?.team.altColorHex) }
    private var homeFirst: Bool { (game.leaguePath ?? "").hasPrefix("soccer") || (game.leaguePath ?? "").hasPrefix("rugby") }
    private var left: Side { homeFirst ? game.home : game.away }
    private var right: Side { homeFirst ? game.away : game.home }
    private var sport: SportID? { game.leaguePath.flatMap(Catalog.league)?.sport }

    var body: some View {
        Button {
            if let p = game.leaguePath { router.push(.game(path: p, id: game.id)) }
        } label: {
            HStack(spacing: 26) {
                headline.frame(width: 300, alignment: .leading)
                matchup.frame(maxWidth: .infinity)
                sidePanel.frame(width: 300)
            }
            .padding(.horizontal, 26).padding(.vertical, 20)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .shadow(color: color.opacity(0.4), radius: 24, y: 10)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(PressableStyle(hoverScale: 1.008))
        .tilt(2)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [color, color.mix(with: .black, by: 0.5), oppColor.mix(with: .black, by: 0.7)],
                           startPoint: .leading, endPoint: .trailing)
            if let p = sport?.pattern { SportPattern(kind: p, opacity: 0.1) }
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: .topLeading, startRadius: 10, endRadius: 420)
        }
    }

    // MARK: Left: status + result

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusChip
            Spacer(minLength: 0)
            if game.state == .post {
                ResultBanner(game: game, teamID: favID, size: 40)
                    .shadow(color: .black.opacity(0.3), radius: 8)
            } else {
                Text(day.fav.name).font(.system(size: 30, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text([game.note ?? game.competition, game.venue].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12, weight: .semibold)).opacity(0.8).lineLimit(2)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            if game.state == .live {
                Circle().fill(AQ.live).frame(width: 7, height: 7).scaleEffect(pulse ? 1.4 : 0.8).opacity(pulse ? 0.5 : 1)
                    .onAppear { guard !Snapshot.enabled else { return }; withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
            }
            Text(game.state == .live ? "LIVE" : (game.state == .post ? "FULL TIME" : "GAMEDAY"))
                .font(.system(size: 11, weight: .black)).tracking(1.4)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(.white))
    }

    // MARK: Middle: crests + score

    private var matchup: some View {
        HStack(spacing: 18) {
            team(left)
            VStack(spacing: 4) {
                if game.hasScore {
                    Text("\(left.score ?? "0") – \(right.score ?? "0")")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .shadow(color: .black.opacity(0.3), radius: 8)
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(Fmt.time(game.date)).font(.system(size: 46, weight: .heavy, design: .rounded)).monospacedDigit()
                }
                Text(statusLine).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(game.state == .live ? Color(hex: "FF6B60") : .white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(minWidth: 150)
            team(right)
        }
    }

    private func team(_ s: Side) -> some View {
        VStack(spacing: 8) {
            FloatingCrest(team: s.team, size: 70, glow: Color.team(s.team.colorHex, alt: s.team.altColorHex))
            Text(s.team.shortName).font(.system(size: 14, weight: s.team.id == favID ? .black : .bold)).lineLimit(1)
        }
        .frame(width: 120)
        .opacity(game.isLoser(s) ? 0.75 : 1)
    }

    private var statusLine: String {
        switch game.state {
        case .live: return game.detail.isEmpty ? game.liveLabel : game.detail
        case .post: return game.seriesSummary ?? (game.shortDetail.isEmpty ? "Final" : game.shortDetail)
        case .pre:
            let mins = Int(game.date.timeIntervalSinceNow / 60)
            if mins <= 0 { return "Starting soon" }
            return mins < 60 ? "Starts in \(mins) min" : "Starts in \(mins / 60) h \(mins % 60) min"
        }
    }

    // MARK: Right: quick stats or pre-match form

    @ViewBuilder private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let d = day.detail, game.state != .pre, !d.teamStats.isEmpty {
                ForEach(Array(quickStats(d).enumerated()), id: \.element.id) { i, s in
                    StatBar(label: s.label, left: homeFirst ? s.home : s.away, right: homeFirst ? s.away : s.home,
                            leftColor: Color.team(left.team.colorHex, alt: left.team.altColorHex),
                            rightColor: Color.kit(away: right.team, home: left.team)).appear(i)
                }
            } else {
                Text("FORM").font(.system(size: 10, weight: .heavy)).tracking(0.8).opacity(0.7)
                HStack(spacing: 5) {
                    ForEach(Array(day.feed.results.prefix(5).reversed().enumerated()), id: \.element.id) { i, g in
                        if let o = g.outcome(for: favID) { OutcomeBadge(outcome: o, size: 24).appear(i) }
                    }
                }
                Text("STANDING").font(.system(size: 10, weight: .heavy)).tracking(0.8).opacity(0.7).padding(.top, 4)
                Text(day.feed.standingSummary ?? day.feed.record ?? "–").font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Spacer()
                Text("Match centre").font(.system(size: 12, weight: .bold))
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
            }
            .opacity(0.85)
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    /// The three most telling numbers: possession/shots for football, the first lines otherwise.
    private func quickStats(_ d: GameDetail) -> [StatLine] {
        let preferred = ["possession", "on goal", "shots", "corner", "field goal", "rebounds", "total yards", "hits", "power play"]
        // Percentages other than possession read badly as bars.
        let usable = d.teamStats.filter { !$0.label.contains("%") || $0.label.lowercased().contains("possession") || $0.label.lowercased().contains("field goal") }
        var picked: [StatLine] = []
        for p in preferred {
            if let s = usable.first(where: { $0.label.lowercased().contains(p) && !picked.contains($0) }) { picked.append(s) }
            if picked.count == 3 { break }
        }
        for s in usable where picked.count < 3 && !picked.contains(s) { picked.append(s) }
        return picked
    }
}
