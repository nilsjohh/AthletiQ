import SwiftUI

/// Lineups for a game: pitch (football), courts (basketball) or grouped lists (hockey and others).
struct LineupSection: View {
    let detail: GameDetail
    var compact = false

    private var home: Lineup? { detail.lineup(for: detail.game.home.team.id) }
    private var away: Lineup? { detail.lineup(for: detail.game.away.team.id) }

    var body: some View {
        if let h = home, let a = away {
            VStack(alignment: .leading, spacing: 14) {
                if !compact { SectionTitle("Lineups") }
                switch h.style {
                case .pitch:
                    FootballPitch(home: h, away: a, homeTeam: detail.game.home.team, awayTeam: detail.game.away.team, compact: compact)
                    if !compact { BenchLists(home: h, away: a, homeTeam: detail.game.home.team, awayTeam: detail.game.away.team) }
                case .court:
                    HStack(alignment: .top, spacing: 18) {
                        CourtCard(lineup: a, team: detail.game.away.team)
                        CourtCard(lineup: h, team: detail.game.home.team)
                    }
                case .groups:
                    HStack(alignment: .top, spacing: 18) {
                        GroupsCard(lineup: a, team: detail.game.away.team)
                        GroupsCard(lineup: h, team: detail.game.home.team)
                    }
                }
            }
        }
    }
}

// MARK: - Football

struct FootballPitch: View {
    let home: Lineup
    let away: Lineup
    let homeTeam: TeamInfo
    let awayTeam: TeamInfo
    var compact = false
    @State private var shown = Snapshot.enabled

    private var homeColor: Color { Color.team(homeTeam.colorHex, alt: homeTeam.altColorHex) }
    /// Away switches to its alternate kit (or dark) when the colours clash.
    private var awayColor: Color { Color.kit(away: awayTeam, home: homeTeam) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                teamHeader(homeTeam, home.formation, leading: true)
                Spacer()
                teamHeader(awayTeam, away.formation, leading: false)
            }
            GeometryReader { geo in
                ZStack {
                    PitchSurface()
                    side(home, color: homeColor, size: geo.size, isHome: true)
                    side(away, color: awayColor, size: geo.size, isHome: false)
                }
            }
            .aspectRatio(compact ? 1.9 : 1.6, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true } }
    }

    private func teamHeader(_ t: TeamInfo, _ formation: String?, leading: Bool) -> some View {
        HStack(spacing: 8) {
            if !leading, let f = formation { Text(f).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(AQ.secondary) }
            TeamLogo(team: t, size: 26)
            Text(t.shortName).font(.system(size: 15, weight: .bold))
            if leading, let f = formation { Text(f).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(AQ.secondary) }
        }
    }

    /// Home attacks left → right; away attacks right → left.
    private func side(_ lineup: Lineup, color: Color, size: CGSize, isHome: Bool) -> some View {
        let rows = lineup.pitchRows
        let n = max(rows.count - 1, 1)
        return ZStack {
            ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                ForEach(Array(row.enumerated()), id: \.element.id) { pi, p in
                    let depth = 0.05 + 0.40 * Double(ri) / Double(n)
                    let x = isHome ? depth : 1 - depth
                    // A team's left is the top of the screen when attacking right.
                    let slot = (Double(pi) + 1) / Double(row.count + 1)
                    let y = isHome ? slot : 1 - slot
                    PitchPlayer(player: p, color: color, compact: compact)
                        .position(x: x * size.width, y: y * size.height)
                        .scaleEffect(shown ? 1 : 0.2)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(ri) * 0.08 + Double(pi) * 0.03 + (isHome ? 0 : 0.2)), value: shown)
                }
            }
        }
    }
}

struct PitchSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1F7A3A"), Color(hex: "16612D")], startPoint: .top, endPoint: .bottom)
            // mown stripes
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { i in
                        Rectangle().fill(.white.opacity(i % 2 == 0 ? 0.035 : 0)).frame(width: g.size.width / 12)
                    }
                }
            }
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let s = GraphicsContext.Shading.color(.white.opacity(0.55))
                let lw: CGFloat = 1.6
                let inset: CGFloat = 10
                let field = CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset)
                ctx.stroke(Path(field), with: s, lineWidth: lw)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: w / 2, y: inset)); p.addLine(to: CGPoint(x: w / 2, y: h - inset)) }, with: s, lineWidth: lw)
                let r = h * 0.15
                ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - r, y: h / 2 - r, width: 2 * r, height: 2 * r)), with: s, lineWidth: lw)
                ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - 3, y: h / 2 - 3, width: 6, height: 6)), with: s)
                for left in [true, false] {
                    let boxW = field.width * 0.15, boxH = field.height * 0.58
                    let smallW = field.width * 0.055, smallH = field.height * 0.28
                    let x0 = left ? field.minX : field.maxX - boxW
                    let xs = left ? field.minX : field.maxX - smallW
                    ctx.stroke(Path(CGRect(x: x0, y: h / 2 - boxH / 2, width: boxW, height: boxH)), with: s, lineWidth: lw)
                    ctx.stroke(Path(CGRect(x: xs, y: h / 2 - smallH / 2, width: smallW, height: smallH)), with: s, lineWidth: lw)
                    var arc = Path()
                    let cx = left ? field.minX + field.width * 0.105 : field.maxX - field.width * 0.105
                    arc.addArc(center: CGPoint(x: cx, y: h / 2), radius: h * 0.13,
                               startAngle: .degrees(left ? -53 : 127), endAngle: .degrees(left ? 53 : 233), clockwise: false)
                    ctx.stroke(arc, with: s, lineWidth: lw)
                }
            }
        }
    }
}

struct PitchPlayer: View {
    let player: LineupPlayer
    let color: Color
    var compact = false
    @State private var hovering = false

    var body: some View {
        let d: CGFloat = compact ? 28 : 36
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Circle().fill(color.gradient)
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                    .overlay(Text(player.jersey ?? "").font(.system(size: d * 0.4, weight: .heavy, design: .rounded)).foregroundStyle(.white))
                    .frame(width: d, height: d)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                if player.subbedOut {
                    Image(systemName: "arrow.down").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Circle().fill(AQ.loss)).offset(x: 4, y: -4)
                }
            }
            Text(player.label)
                .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(.black.opacity(hovering ? 0.55 : 0.35)))
        }
        .frame(width: compact ? 84 : 100)
        .scaleEffect(hovering ? 1.15 : 1)
        .animation(AQ.spring, value: hovering)
        .onHover { hovering = $0 }
        .help("\(player.name)\(player.positionName.map { " · \($0)" } ?? "")")
    }
}

struct BenchLists: View {
    let home: Lineup
    let away: Lineup
    let homeTeam: TeamInfo
    let awayTeam: TeamInfo

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            list(home, homeTeam)
            list(away, awayTeam)
        }
    }

    private func list(_ l: Lineup, _ t: TeamInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { TeamLogo(team: t, size: 20); Text("Substitutes").font(.headline) }
            ForEach(Array(l.bench.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 10) {
                    Text(p.jersey ?? "").font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(AQ.secondary).frame(width: 24, alignment: .leading)
                    Text(p.name).font(.system(size: 13, weight: p.subbedIn ? .semibold : .regular))
                    Spacer()
                    if p.subbedIn {
                        Label("On", systemImage: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(AQ.win)
                    }
                }
                .appear(i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Basketball

struct CourtCard: View {
    let lineup: Lineup
    let team: TeamInfo
    @State private var shown = Snapshot.enabled

    private var color: Color { Color.team(team.colorHex, alt: team.altColorHex) }

    /// Guards up top, forwards on the wings, the last player in the post.
    private var placed: [(LineupPlayer, CGPoint)] {
        let order: [String: Int] = ["PG": 0, "G": 0, "SG": 1, "SF": 2, "F": 2, "PF": 3, "C": 4]
        let five = Array(lineup.starters.sorted { (order[$0.position ?? ""] ?? 3) < (order[$1.position ?? ""] ?? 3) }.prefix(5))
        let slots = [CGPoint(x: 0.3, y: 0.24), CGPoint(x: 0.7, y: 0.24), CGPoint(x: 0.13, y: 0.6), CGPoint(x: 0.87, y: 0.6), CGPoint(x: 0.5, y: 0.74)]
        return Array(zip(five, slots))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { TeamLogo(team: team, size: 24); Text(team.shortName).font(.headline); Spacer(); Text("Starting five").font(.caption.weight(.semibold)).foregroundStyle(AQ.secondary) }
            GeometryReader { g in
                ZStack {
                    LinearGradient(colors: [Color(hex: "C98A4B"), Color(hex: "A86B33")], startPoint: .top, endPoint: .bottom)
                    SportPattern(kind: .court, opacity: 0.5, lineWidth: 1.5).rotationEffect(.degrees(90)).scaleEffect(1.6).offset(y: g.size.height * 0.45)
                    ForEach(Array(placed.enumerated()), id: \.offset) { i, item in
                        PitchPlayer(player: item.0, color: color)
                            .position(x: item.1.x * g.size.width, y: item.1.y * g.size.height)
                            .scaleEffect(shown ? 1 : 0.2).opacity(shown ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.06), value: shown)
                    }
                }
            }
            .aspectRatio(1.25, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !lineup.bench.isEmpty {
                Text("Bench").font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(AQ.secondary)
                FlowRow(items: lineup.bench.map { "\($0.jersey.map { "#\($0) " } ?? "")\($0.label)" })
            }
        }
        .frame(maxWidth: .infinity)
        .card()
        .onAppear { withAnimation { shown = true } }
    }
}

// MARK: - Grouped (hockey and others)

struct GroupsCard: View {
    let lineup: Lineup
    let team: TeamInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { TeamLogo(team: team, size: 24); Text(team.shortName).font(.headline) }
            let groups = lineup.groups.isEmpty ? [LineupGroup(name: "Starters", players: lineup.starters), LineupGroup(name: "Bench", players: lineup.bench)] : lineup.groups
            ForEach(groups) { g in
                if !g.players.isEmpty {
                    Text(g.name.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(AQ.secondary)
                    FlowRow(items: g.players.map { "\($0.jersey.map { "#\($0) " } ?? "")\($0.label)" })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Simple wrapping row of name chips.
struct FlowRow: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                Text(s).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(AQ.fill))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Result banner

/// "ARSENAL WIN" when a favourite team wins; otherwise the final score line.
struct ResultBanner: View {
    let game: Game
    let teamID: String
    var size: CGFloat = 64
    @State private var shine = false

    var body: some View {
        if let o = game.outcome(for: teamID), let me = game.side(of: teamID), let opp = game.opponent(of: teamID) {
            if o == .win {
                Text("\(me.team.shortName.uppercased()) WIN")
                    .font(.system(size: size, weight: .black))
                    .tracking(-1)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .overlay {
                        LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 120)
                            .offset(x: shine ? 500 : -500)
                            .mask(Text("\(me.team.shortName.uppercased()) WIN").font(.system(size: size, weight: .black)).tracking(-1))
                    }
                    .onAppear {
                        guard !Snapshot.enabled else { return }
                        withAnimation(.easeInOut(duration: 1.6).delay(0.4).repeatForever(autoreverses: false)) { shine = true }
                    }
            } else {
                let home = game.home, away = game.away
                Text("\(home.team.shortName) \(home.score ?? "")–\(away.score ?? "") \(away.team.shortName)")
                    .font(.system(size: size * 0.6, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityLabel(o == .draw ? "Draw against \(opp.team.name)" : "Defeat against \(opp.team.name)")
            }
        }
    }
}
