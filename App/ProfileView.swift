import SwiftUI

@Observable @MainActor
final class ProfileState {
    static let shared = ProfileState()
    var isPresented = !UserDefaults.standard.bool(forKey: "qProfileDone")
    func finish() {
        UserDefaults.standard.set(true, forKey: "qProfileDone")
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { isPresented = false }
    }
    func open() { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { isPresented = true } }
}

/// First-run setup: pick favourite leagues, then teams. Re-openable from Home.
struct QProfileView: View {
    enum Step: Int { case welcome, leagues, teams }

    @State private var step: Step
    @State private var leagues: Set<String> = Set(Favorites.shared.leagues)
    @State private var teams: [String: (TeamInfo, String)] = [:]   // "path|id" → (team, path)
    @State private var sportFilter: SportID?
    @State private var teamLists: [String: [TeamInfo]] = [:]
    @State private var search = ""
    @State private var forward = true
    @Namespace private var ns

    private var profile: ProfileState { ProfileState.shared }

    init(startStep: Step = .welcome, preload: [String: [TeamInfo]] = [:]) {
        _step = State(initialValue: startStep)
        _teamLists = State(initialValue: preload)
    }

    /// Leagues shown for team picking: chosen team leagues, or a popular set if none chosen.
    private var teamLeagues: [LeagueRef] {
        let chosen = Catalog.leagues.filter { leagues.contains($0.path) && $0.kind == .team && !$0.isCollege && !$0.name.contains("Cup") && !["Europe", "World", "South America"].contains($0.region) }
        if !chosen.isEmpty { return chosen }
        return ["soccer/eng.1", "soccer/esp.1", "basketball/nba", "football/nfl"].compactMap(Catalog.league)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                ZStack {
                    switch step {
                    case .welcome: welcome.transition(slide)
                    case .leagues: leaguePicker.transition(slide)
                    case .teams: teamPicker.transition(slide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        // Background layers never affect layout (the glows are wider than a phone).
        .background {
            ZStack { AQ.bg; AuroraBackground() }
                .clipped()
                .ignoresSafeArea()
        }
        .onAppear {
            for t in Favorites.shared.teams {
                teams["\(t.key.leaguePath)|\(t.key.id)"] = (TeamInfo(id: t.key.id, abbreviation: "", name: t.name, shortName: t.name,
                                                                      colorHex: t.colorHex, altColorHex: nil, logo: t.logo), t.key.leaguePath)
            }
        }
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(_ s: Step) {
        forward = s.rawValue > step.rawValue
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { step = s }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            if step != .welcome {
                Button { go(Step(rawValue: step.rawValue - 1) ?? .welcome) } label: {
                    Label("Back", systemImage: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(LinkStyle())
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i == step.rawValue ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: i == step.rawValue ? 22 : 7, height: 7)
                }
            }
            .animation(AQ.spring, value: step)
            Spacer()
            Button("Skip") { save(); profile.finish() }.buttonStyle(LinkStyle()).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AQ.secondary)
        }
        .padding(.horizontal, ph(30, 16)).padding(.top, 22).padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            Group {
                switch step {
                case .welcome: EmptyView()
                case .leagues: Text("\(leagues.count) selected")
                case .teams: Text("\(teams.count) selected")
                }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(AQ.secondary)
            .contentTransition(.numericText())
            Spacer()
            Button {
                switch step {
                case .welcome: go(.leagues)
                case .leagues: go(.teams)
                case .teams: save(); profile.finish()
                }
            } label: {
                Text(step == .teams ? "Done" : (step == .welcome ? "Get started" : "Continue"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AQ.bg)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(Color.primary))
            }
            .buttonStyle(PressableStyle(hoverScale: 1.05, pressScale: 0.94))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, ph(30, 16)).padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            AppMark(size: 96).shadow(color: .black.opacity(0.3), radius: 24, y: 10).appear(0)
            Text("Your Q Profile").font(.system(size: ph(52, 36), weight: .heavy)).appear(1)
            Text("Pick the leagues and teams you love.\nThey're pinned on Home, and your teams get a Gameday when they play.")
                .font(.system(size: 17, weight: .medium)).foregroundStyle(AQ.secondary)
                .multilineTextAlignment(.center).appear(2)
            HStack(spacing: ph(14, 8)) {
                ForEach(Array([SportID.football, .basketball, .americanFootball, .hockey, .baseball, .motorsport].enumerated()), id: \.element) { i, s in
                    Image(systemName: s.symbol).font(.system(size: ph(24, 19), weight: .light))
                        .frame(width: ph(58, 44), height: ph(58, 44))
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: s.primaryHex).gradient))
                        .foregroundStyle(.white)
                        .appear(i + 3)
                }
            }
            .padding(.top, 8)
        }
        .padding(40)
    }

    private var leaguePicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose your leagues").font(.system(size: ph(34, 28), weight: .heavy))
                Text("Follow as many as you like.").foregroundStyle(AQ.secondary)
            }
            .padding(.horizontal, ph(30, 16))
            HScroll {
                HStack(spacing: 8) {
                    chip(nil, "All")
                    ForEach(SportID.allCases) { s in chip(s, s.name) }
                }
                .padding(.horizontal, ph(30, 16))
            }
            VScroll {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: gm(240)), spacing: 14)], spacing: 14) {
                    ForEach(Array(Catalog.leagues.filter { sportFilter == nil || $0.sport == sportFilter }.enumerated()), id: \.element.id) { i, l in
                        LeagueChoice(league: l, selected: leagues.contains(l.path)) {
                            withAnimation(AQ.spring) { if leagues.contains(l.path) { leagues.remove(l.path) } else { leagues.insert(l.path) } }
                        }
                        .appear(i)
                    }
                }
                .padding(.horizontal, ph(30, 16)).padding(.vertical, 6)
            }
        }
        .padding(.top, 10)
    }

    private func chip(_ s: SportID?, _ title: String) -> some View {
        let on = sportFilter == s
        return Button { withAnimation(AQ.spring) { sportFilter = s } } label: {
            HStack(spacing: 6) {
                if let s { Image(systemName: s.symbol).font(.system(size: 12, weight: .light)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(on ? AQ.bg : .primary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background {
                if on { Capsule().fill(Color.primary).matchedGeometryEffect(id: "chip", in: ns) }
                else { Capsule().fill(AQ.fill) }
            }
        }
        .buttonStyle(PressableStyle(hoverScale: 1.04, pressScale: 0.94))
    }

    private var teamPicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            AdaptiveStack(spacing: 12, alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick your teams").font(.system(size: ph(34, 28), weight: .heavy))
                    Text("Your teams get Gameday coverage on Home.").foregroundStyle(AQ.secondary)
                }
                if !Device.isPhone { Spacer() }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AQ.secondary)
                    TextField("Search teams", text: $search).textFieldStyle(.plain).frame(width: Device.isPhone ? nil : 200)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(AQ.fill))
            }
            .padding(.horizontal, ph(30, 16))
            VScroll {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(teamLeagues) { l in
                        let list = (teamLists[l.path] ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                        if teamLists[l.path] == nil || !list.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    LeagueLogo(league: l, size: 22)
                                    Text(l.name).font(.system(size: 16, weight: .bold))
                                }
                                if teamLists[l.path] == nil {
                                    RoundedRectangle(cornerRadius: 16).fill(AQ.fill).frame(height: 70).shimmer()
                                } else {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ph(150, 100)), spacing: 12)], spacing: 12) {
                                        ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                                            let k = "\(l.path)|\(t.id)"
                                            TeamChoice(team: t, selected: teams[k] != nil) {
                                                withAnimation(AQ.spring) { if teams[k] != nil { teams[k] = nil } else { teams[k] = (t, l.path) } }
                                            }
                                            .appear(i)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ph(30, 16)).padding(.vertical, 6)
            }
        }
        .padding(.top, 10)
        .task(id: teamLeagues.map(\.path).joined()) {
            await withTaskGroup(of: (String, [TeamInfo]).self) { g in
                for l in teamLeagues where teamLists[l.path] == nil { g.addTask { (l.path, await ESPN.teams(l)) } }
                for await (p, list) in g { withAnimation(AQ.snappy) { teamLists[p] = list } }
            }
        }
    }

    private func save() {
        let fav = Favorites.shared
        for l in Catalog.leagues {
            let want = leagues.contains(l.path)
            if want != fav.isFavorite(league: l.path) { fav.toggle(league: l.path) }
        }
        let wanted = Set(teams.keys)
        for t in fav.teams where !wanted.contains("\(t.key.leaguePath)|\(t.key.id)") {
            fav.toggle(team: TeamInfo(id: t.key.id, abbreviation: "", name: t.name, shortName: t.name, colorHex: t.colorHex, altColorHex: nil, logo: t.logo), key: t.key)
        }
        for (_, (info, path)) in teams {
            let key = TeamKey(leaguePath: path, id: info.id)
            if !fav.isFavorite(team: key) { fav.toggle(team: info, key: key) }
        }
    }
}

struct LeagueChoice: View {
    let league: LeagueRef
    let selected: Bool
    let action: () -> Void
    var body: some View {
        let c = Color(hex: league.colorHex)
        Button(action: action) {
            HStack(spacing: 12) {
                LeagueLogo(league: league, size: 34)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.name).font(.system(size: 14, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    Text(league.region.isEmpty ? league.sport.name : league.region).font(.system(size: 11.5)).opacity(0.7)
                }
                Spacer(minLength: 0)
                SelectMark(on: selected)
            }
            .padding(12)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [c.opacity(selected ? 0.95 : 0.6), c.mix(with: .black, by: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(selected ? 0.8 : 0.1), lineWidth: selected ? 2 : 1))
            .scaleEffect(selected ? 1.0 : 0.98)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.03, pressScale: 0.94))
    }
}

struct TeamChoice: View {
    let team: TeamInfo
    let selected: Bool
    let action: () -> Void
    var body: some View {
        let c = Color.team(team.colorHex, alt: team.altColorHex)
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    TeamLogo(team: team, size: 50)
                        .padding(10)
                        .background(Circle().fill(selected ? c.opacity(0.35) : AQ.fill))
                        .overlay(Circle().strokeBorder(selected ? c : .clear, lineWidth: 2.5))
                    SelectMark(on: selected, size: 20).offset(x: 6, y: -2)
                }
                Text(team.shortName).font(.system(size: 12.5, weight: selected ? .bold : .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? c.opacity(0.12) : .clear))
        }
        .buttonStyle(PressableStyle(hoverScale: 1.05, pressScale: 0.92))
    }
}

/// Animated tick that pops when selected.
struct SelectMark: View {
    let on: Bool
    var size: CGFloat = 24
    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(on ? 0 : 0.45), lineWidth: 1.5)
            Circle().fill(.white).scaleEffect(on ? 1 : 0.01)
            Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .black)).foregroundStyle(.black)
                .scaleEffect(on ? 1 : 0.01)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: on)
    }
}

/// Slow-drifting colour glow behind the profile setup.
struct AuroraBackground: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "0E7A3E").opacity(0.35)).frame(width: 520).blur(radius: 120)
                .offset(x: drift ? -260 : -120, y: drift ? -180 : -60)
            Circle().fill(Color(hex: "1D428A").opacity(0.35)).frame(width: 480).blur(radius: 120)
                .offset(x: drift ? 280 : 140, y: drift ? 120 : 220)
            Circle().fill(Color(hex: "D40000").opacity(0.22)).frame(width: 420).blur(radius: 120)
                .offset(x: drift ? 60 : 200, y: drift ? -240 : -120)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !Snapshot.enabled else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
