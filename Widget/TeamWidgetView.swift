import WidgetKit
import SwiftUI

struct TeamWidgetView: View {
    let entry: TeamEntry
    /// Lets offscreen previews pick a size.
    var forcedFamily: WidgetFamily? = nil
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { forcedFamily ?? envFamily }

    private var teamID: String { entry.key.id }
    private var full: Bool { mode == .fullColor }
    private var fg: Color { full ? .white : .primary }
    private var dim: Color { fg.opacity(0.62) }
    private var info: TeamInfo? { entry.feed?.info }
    private var color: Color { Color.team(info?.colorHex, alt: info?.altColorHex, fallback: Color(hex: entry.key.league?.colorHex ?? "3A3A3C")) }
    private var homeFirst: Bool { entry.key.leaguePath.hasPrefix("soccer") || entry.key.leaguePath.hasPrefix("rugby") }

    var body: some View {
        Group {
            if let feed = entry.feed {
                switch family {
                case .systemSmall: small(feed)
                case .systemMedium: medium(feed)
                default: large(feed)
                }
            } else {
                offline
            }
        }
        .foregroundStyle(fg)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { background }
    }

    // MARK: Sizes

    private func small(_ feed: TeamFeed) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                crest(info, 30, accented: true)
                Spacer()
                if let pos = feed.position { Text(Fmt.ordinal(pos.rank)).font(.system(size: 13, weight: .heavy)).foregroundStyle(dim) }
            }
            Spacer(minLength: 0)
            if let g = feed.live ?? feed.upcoming.first {
                let opp = g.opponent(of: teamID)
                HStack(spacing: 6) {
                    crest(opp?.team, 18)
                    Text("\(g.side(of: teamID)?.isHome == true ? "vs" : "@") \(opp?.team.shortName ?? "")")
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                }
                if g.state == .live {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(g.side(of: teamID)?.score ?? "0")–\(opp?.score ?? "0")")
                            .font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit().widgetAccentable()
                        liveBadge(g)
                    }
                } else {
                    Text(Fmt.time(g.date)).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().widgetAccentable()
                    Text(Fmt.day(g.date)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(dim)
                }
            } else if let r = feed.results.first {
                resultRow(r)
            }
        }
    }

    private func medium(_ feed: TeamFeed) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header(feed, compact: true)
                Spacer(minLength: 0)
                if let g = feed.live ?? feed.upcoming.first { bigMatch(g) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(fg.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                label("RESULTS")
                ForEach(feed.results.prefix(3)) { resultRow($0) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func large(_ feed: TeamFeed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(feed, compact: false)
            Spacer(minLength: 6)
            label(feed.live != nil ? "LIVE" : "NEXT")
            VStack(spacing: 5) {
                if let live = feed.live { liveRow(live) }
                ForEach(feed.upcoming.prefix(feed.live == nil ? 2 : 1)) { fixtureRow($0) }
                if feed.upcoming.isEmpty && feed.live == nil { Text("No fixtures scheduled").font(.system(size: 12)).foregroundStyle(dim) }
            }
            Spacer(minLength: 6)
            label("RESULTS")
            VStack(spacing: 5) { ForEach(feed.results.prefix(2)) { resultRow($0) } }
            Spacer(minLength: 6)
            if let table = feed.table, let tl = feed.tableLeaguePath.flatMap(Catalog.league) ?? entry.key.league {
                tableSection(table, league: tl)
            }
        }
    }

    // MARK: Pieces

    private func header(_ feed: TeamFeed, compact: Bool) -> some View {
        HStack(spacing: 8) {
            crest(info, compact ? 24 : 26, accented: true)
            Text(compact ? (info?.shortName ?? "") : (info?.name ?? "")).font(.system(size: compact ? 15 : 17, weight: .heavy)).lineLimit(1).widgetAccentable()
            Spacer(minLength: 4)
            if entry.isStale {
                HStack(spacing: 3) { Image(systemName: "wifi.slash"); Text(Fmt.time(feed.updated)) }
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(dim)
            } else if !compact, let pos = feed.position {
                let usesPoints = [.soccer, .rugby, .hockey].contains(entry.key.league?.tableStyle ?? .basketball)
                Text("\(Fmt.ordinal(pos.rank))\(usesPoints ? (pos.display["points"].map { " · \($0) pts" } ?? "") : (feed.record.map { " · \($0)" } ?? ""))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(dim)
            } else if !compact, let r = feed.record {
                Text(r).font(.system(size: 12, weight: .semibold)).foregroundStyle(dim)
            }
        }
    }

    private func label(_ text: String, trailing: AnyView? = nil) -> some View {
        HStack {
            Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.8)
                .foregroundStyle(text == "LIVE" && full ? AnyShapeStyle(Color(hex: "FF5A52")) : AnyShapeStyle(dim))
            Spacer()
            trailing
        }
        .padding(.bottom, 4)
    }

    private func bigMatch(_ g: Game) -> some View {
        let (l, r) = homeFirst ? (g.home, g.away) : (g.away, g.home)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                crest(l.team, 30)
                if g.state == .live {
                    Text("\(l.score ?? "0")–\(r.score ?? "0")").font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit().widgetAccentable()
                } else {
                    Text(Fmt.time(g.date)).font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit().widgetAccentable()
                }
                crest(r.team, 30)
            }
            HStack(spacing: 6) {
                if g.state == .live { liveBadge(g) } else { Text(Fmt.day(g.date)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(dim) }
                Text(g.competition ?? "").font(.system(size: 10.5)).foregroundStyle(dim).lineLimit(1)
            }
        }
    }

    private func liveBadge(_ g: Game) -> some View {
        HStack(spacing: 4) {
            Circle().frame(width: 5, height: 5)
            Text(g.liveLabel).font(.system(size: 10.5, weight: .heavy)).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(full ? .white : fg)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(Capsule().fill(full ? AnyShapeStyle(Color.red) : AnyShapeStyle(fg.opacity(0.18))))
        .widgetAccentable()
    }

    private func liveRow(_ g: Game) -> some View {
        let (l, r) = homeFirst ? (g.home, g.away) : (g.away, g.home)
        return HStack(spacing: 8) {
            crest(l.team, 24)
            Text("\(l.score ?? "0") – \(r.score ?? "0")").font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit().widgetAccentable()
            crest(r.team, 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(g.opponent(of: teamID)?.team.shortName ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(g.competition ?? "").font(.system(size: 10)).foregroundStyle(dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            liveBadge(g)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fg.opacity(0.1)))
    }

    private func fixtureRow(_ g: Game) -> some View {
        let opp = g.opponent(of: teamID)
        let home = g.side(of: teamID)?.isHome == true
        return HStack(spacing: 8) {
            crest(opp?.team, 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(home ? "vs" : "@") \(opp?.team.shortName ?? "")").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(g.note ?? g.competition ?? "").font(.system(size: 10)).foregroundStyle(dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.shortDay(g.date)).font(.system(size: 12, weight: .semibold)).widgetAccentable()
                Text(Fmt.time(g.date)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(dim)
            }
        }
    }

    private func resultRow(_ g: Game) -> some View {
        let opp = g.opponent(of: teamID)
        let me = g.side(of: teamID)
        return HStack(spacing: 7) {
            if let o = g.outcome(for: teamID) { badge(o) }
            crest(opp?.team, 18)
            Text(family == .systemLarge ? "\(me?.isHome == true ? "vs" : "@") \(opp?.team.shortName ?? "")" : (opp?.team.abbreviation ?? ""))
                .font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(me?.score ?? "–")–\(opp?.score ?? "–")").font(.system(size: 13.5, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7).widgetAccentable()
            if family == .systemLarge {
                Text(Fmt.shortDay(g.date)).font(.system(size: 11)).foregroundStyle(dim).frame(width: 46, alignment: .trailing)
            }
        }
    }

    private func badge(_ o: Outcome) -> some View {
        let c: Color = o == .win ? Color(hex: "30D158") : (o == .draw ? Color(hex: "8E8E93") : Color(hex: "FF453A"))
        return Text(o.rawValue)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(full ? .white : fg)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(full ? AnyShapeStyle(c) : AnyShapeStyle(fg.opacity(o == .win ? 0.35 : 0.15))))
            .widgetAccentable(o == .win)
    }

    private func tableSection(_ table: StandingsGroup, league: LeagueRef) -> some View {
        let cols = StandingColumn.compact(for: league.tableStyle)
        return VStack(spacing: 0) {
            label((table.name.count < 28 ? table.name : league.name).uppercased(), trailing: AnyView(
                HStack(spacing: 0) { ForEach(cols) { Text($0.label).frame(width: $0.width, alignment: .trailing) } }
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(dim).padding(.trailing, 6)
            ))
            ForEach(table.window(around: teamID, count: 5)) { row in
                let mine = row.team.id == teamID
                HStack(spacing: 6) {
                    Text("\(row.rank)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(mine ? fg : dim).frame(width: 18, alignment: .trailing)
                    crest(row.team, 14, accented: mine)
                    Text(row.team.shortName).font(.system(size: 12, weight: mine ? .bold : .medium)).lineLimit(1)
                    Spacer(minLength: 2)
                    ForEach(cols) { c in
                        Text(c.format(row.value(c.key)))
                            .font(.system(size: c.emphasized ? 12 : 11, weight: c.emphasized ? .bold : .regular)).monospacedDigit()
                            .foregroundStyle(c.emphasized || mine ? fg : dim)
                            .frame(width: c.width, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(mine ? fg.opacity(full ? 0.16 : 0.14) : .clear))
                .widgetAccentable(mine)
            }
        }
    }

    @ViewBuilder
    private func crest(_ team: TeamInfo?, _ size: CGFloat, accented: Bool = false) -> some View {
        let urls = [team?.darkLogo, team?.logo].compactMap { $0 }
        if let img = urls.lazy.compactMap({ entry.logos[$0] }).first {
            Image(decorative: img, scale: 2)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(accented ? .accentedDesaturated : .desaturated)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Circle().fill(fg.opacity(0.18)).frame(width: size * 0.8, height: size * 0.8).frame(width: size, height: size)
        }
    }

    var background: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [color.mix(with: .white, by: 0.05), color.mix(with: .black, by: 0.55), Color(hex: "0E0E10")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let l = [info?.darkLogo, info?.logo].compactMap({ $0 }).lazy.compactMap({ entry.logos[$0] }).first {
                Image(decorative: l, scale: 2).resizable().scaledToFit()
                    .frame(width: family == .systemSmall ? 120 : 210, height: family == .systemSmall ? 120 : 210)
                    .opacity(0.08).rotationEffect(.degrees(-10))
                    .offset(x: 50, y: -40)
            }
        }
    }

    private var offline: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt.fill").font(.system(size: 28))
            Text("AthletiQ").font(.system(size: 15, weight: .heavy))
            Text("Can't reach the score service.\nTrying again shortly.").font(.system(size: 11)).foregroundStyle(dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
