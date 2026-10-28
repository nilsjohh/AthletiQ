import SwiftUI

// MARK: - Images

@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private var cache: [URL: NSImage] = [:]
    private var misses: Set<URL> = []
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { cache[url] }

    func image(_ url: URL) async -> NSImage? {
        if let i = cache[url] { return i }
        if misses.contains(url) { return nil }
        if let t = inflight[url] { return await t.value }
        let task = Task<NSImage?, Never> {
            guard let cg = await Thumb.download(url, maxPixel: 320) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { cache[url] = result } else { misses.insert(url) }
        return result
    }
}

/// Crest, flag or headshot. Prefers dark-background variants (the app is dark).
struct RemoteImage: View {
    var urls: [URL]
    var size: CGFloat
    var circular = false
    var placeholder: String? = nil
    @State private var image: NSImage?

    init(_ urls: [URL?], size: CGFloat, circular: Bool = false, placeholder: String? = nil) {
        self.urls = urls.compactMap { $0 }
        self.size = size
        self.circular = circular
        self.placeholder = placeholder
        _image = State(initialValue: self.urls.lazy.compactMap { ImageStore.shared.cached($0) }.first)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: circular ? .fill : .fit)
                    .frame(width: size, height: size)
                    .clipShape(circular ? AnyShape(Circle()) : AnyShape(Rectangle()))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if let placeholder {
                Image(systemName: placeholder)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(width: size, height: size)
                    .background(circular ? AnyShapeStyle(AQ.fill) : AnyShapeStyle(Color.clear), in: Circle())
            } else {
                Circle().fill(AQ.fill).frame(width: size * 0.8, height: size * 0.8)
            }
        }
        .frame(width: size, height: size)
        .task(id: urls) {
            guard image == nil else { return }
            for u in urls {
                if let i = await ImageStore.shared.image(u) {
                    withAnimation(.easeOut(duration: 0.25)) { image = i }
                    return
                }
            }
        }
    }
}

struct TeamLogo: View {
    let team: TeamInfo?
    var size: CGFloat
    var body: some View {
        RemoteImage([team?.darkLogo, team?.logo], size: size, placeholder: "shield.fill")
    }
}

/// Offscreen rendering for design checks: no scroll views, no entry animations.
enum Snapshot { nonisolated(unsafe) static var enabled = false }

/// Horizontal scroller that lays out flat when rendering offscreen.
struct HScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if Snapshot.enabled { content().frame(maxWidth: .infinity, alignment: .leading).frame(width: 1180, alignment: .leading).clipped() } else { ScrollView(.horizontal, showsIndicators: false) { content() } }
    }
}

// MARK: - Palette

enum AQ {
    /// Colour that follows the system light/dark appearance.
    static func dyn(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let bg = dyn(light: NSColor(red: 0.953, green: 0.953, blue: 0.965, alpha: 1), dark: NSColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1))
    static let card = dyn(light: .white, dark: NSColor(white: 1, alpha: 0.055))
    static let cardHover = dyn(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 1, alpha: 0.085))
    static let stroke = dyn(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.08))
    static let strokeTop = dyn(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.12))
    static let strokeBottom = dyn(light: NSColor(white: 0, alpha: 0.1), dark: NSColor(white: 1, alpha: 0.03))
    static let fill = dyn(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.06))
    static let shadow = dyn(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 0, alpha: 0))
    static let gold = dyn(light: NSColor(red: 0.72, green: 0.53, blue: 0.04, alpha: 1), dark: NSColor(red: 1, green: 0.84, blue: 0.31, alpha: 1))
    static let secondary = Color.primary.opacity(0.6)
    static let tertiary = Color.primary.opacity(0.4)
    static let live = Color(hex: "FF3B30")
    static let win = Color(hex: "30D158")
    static let draw = Color(hex: "8E8E93")
    static let loss = Color(hex: "FF453A")
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let snappy = Animation.snappy(duration: 0.28)
}

// MARK: - Interaction styles

/// Buttons that dip on press and lift on hover — used for every card and link.
struct PressableStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.015
    var pressScale: CGFloat = 0.965
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, hoverScale: hoverScale, pressScale: pressScale)
    }
    private struct PressableBody: View {
        let configuration: Configuration
        let hoverScale: CGFloat
        let pressScale: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressScale : (hovering ? hoverScale : 1))
                .brightness(hovering ? 0.03 : 0)
                .animation(AQ.spring, value: configuration.isPressed)
                .animation(AQ.spring, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Inline text link (team names): highlights on hover, dips on press.
struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration) }
    private struct StyledBody: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : 1)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.5)).frame(height: 1)
                        .scaleEffect(x: hovering ? 1 : 0, anchor: .leading)
                        .offset(y: 2)
                }
                .animation(AQ.snappy, value: hovering)
                .onHover { hovering = $0 }
                .pointerStyle(.link)
        }
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 20
    var tint: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.22), $0.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)) } ?? AnyShapeStyle(AQ.card))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [AQ.strokeTop, AQ.strokeBottom], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: AQ.shadow, radius: 8, y: 3)
            .overlay {
                EmptyView()
            }
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(CardBackground(padding: padding, radius: radius, tint: tint))
    }

    /// Fade-and-rise when first shown, staggered by index.
    func appear(_ index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }
}

struct AppearModifier: ViewModifier {
    let index: Int
    @State private var shown = Snapshot.enabled
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .scaleEffect(shown ? 1 : 0.985)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(min(index, 14)) * 0.035)) { shown = true }
            }
    }
}

/// Minimal country marker (instead of colourful flag images): "USA", "BRA"…
struct CountryTag: View {
    let url: URL?
    var code: String? {
        guard let name = url?.deletingPathExtension().lastPathComponent, name.count <= 4 else { return nil }
        return name.uppercased()
    }
    var body: some View {
        if let code {
            Text(code)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4).padding(.vertical, 1.5)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.secondary.opacity(0.5), lineWidth: 0.8))
        }
    }
}

// MARK: - Common pieces

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    init(_ title: String, trailing: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.trailing = trailing; self.action = action
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 22, weight: .bold))
            Spacer()
            if let trailing {
                if let action {
                    Button(action: action) {
                        HStack(spacing: 3) { Text(trailing); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                            .font(.callout.weight(.semibold)).foregroundStyle(AQ.secondary)
                    }.buttonStyle(LinkStyle())
                } else {
                    Text(trailing).font(.callout).foregroundStyle(AQ.secondary)
                }
            }
        }
    }
}

struct LivePill: View {
    var label: String = "LIVE"
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6)
                .scaleEffect(pulse ? 0.6 : 1).opacity(pulse ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
            Text(label).font(.system(size: 11, weight: .heavy)).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .background(Capsule().fill(AQ.live))
        .shadow(color: AQ.live.opacity(0.5), radius: 8)
        .onAppear { pulse = true }
    }
}

struct OutcomeBadge: View {
    let outcome: Outcome
    var size: CGFloat = 22
    var color: Color { outcome == .win ? AQ.win : (outcome == .draw ? AQ.draw : AQ.loss) }
    var body: some View {
        Text(outcome.rawValue)
            .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.gradient))
    }
}

struct LoadingState: View {
    var label = "Loading"
    @State private var spin = false
    var body: some View {
        VStack(spacing: 22) {
            spinner
            SkeletonPage()
        }
    }
    private var spinner: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(AQ.fill, lineWidth: 4)
                Circle().trim(from: 0, to: 0.28).stroke(Color.primary.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            }
            .frame(width: 30, height: 30)
            Text(label).font(.callout.weight(.medium)).foregroundStyle(AQ.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .onAppear { spin = true }
    }
}

struct EmptyNote: View {
    let text: String
    var symbol = "calendar.badge.exclamationmark"
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(AQ.tertiary)
            Text(text).font(.callout).foregroundStyle(AQ.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .card()
    }
}

/// Animated segmented tabs with a sliding capsule.
struct TabBar<T: Hashable & Identifiable>: View {
    let tabs: [T]
    @Binding var selection: T
    let title: (T) -> String
    var accent: Color = .primary
    var selectedText: Color = .black
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(AQ.spring) { selection = tab }
                } label: {
                    Text(title(tab))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? selectedText : AQ.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule().fill(accent).matchedGeometryEffect(id: "tab", in: ns)
                                    .shadow(color: accent.opacity(0.35), radius: 10)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(AQ.fill))
        .overlay(Capsule().strokeBorder(AQ.stroke))
    }
}

/// Star toggle with a bounce.
struct FavoriteButton: View {
    let isOn: Bool
    let action: () -> Void
    @State private var bump = 0
    @State private var burst = false
    var body: some View {
        Button {
            bump += 1
            let turningOn = !isOn
            withAnimation(AQ.spring) { action() }
            if turningOn {
                burst = false
                withAnimation(.easeOut(duration: 0.6)) { burst = true }
            }
        } label: {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? Color.yellow : .white.opacity(0.85))
                .symbolEffect(.bounce, value: bump)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(isOn ? 0.16 : 0.1)))
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                .background {
                    ZStack {
                        Circle().strokeBorder(Color.yellow.opacity(burst ? 0 : 0.9), lineWidth: burst ? 1 : 3)
                            .scaleEffect(burst ? 2.2 : 0.8)
                        ForEach(0..<8, id: \.self) { i in
                            Circle().fill(Color.yellow).frame(width: 4, height: 4)
                                .offset(y: burst ? -34 : -10)
                                .rotationEffect(.degrees(Double(i) * 45))
                                .opacity(burst ? 0 : (bump > 0 && isOn ? 1 : 0))
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
        .buttonStyle(PressableStyle(hoverScale: 1.08, pressScale: 0.88))
        .help(isOn ? "Remove from favourites" : "Add to favourites")
    }
}

/// Large themed header used across pages.
struct Hero<Content: View>: View {
    let color: Color
    var secondary: Color? = nil
    var pattern: PatternKind? = nil
    var height: CGFloat = 220
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [color.mix(with: .white, by: 0.06), color.mix(with: .black, by: 0.45), (secondary ?? color).mix(with: .black, by: 0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
            if let pattern {
                SportPattern(kind: pattern, opacity: 0.12, lineWidth: 2)
                    .padding(-10)
                    .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
            }
            content().padding(30)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: color.opacity(0.35), radius: 30, y: 14)
        .foregroundStyle(.white)
    }
}

struct Page<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if Snapshot.enabled {
            inner.background(AQ.bg)
        } else {
            ScrollView { inner }
                .scrollIndicators(.automatic)
                .background(AQ.bg)
        }
    }
    private var inner: some View {
        VStack(alignment: .leading, spacing: 28) { content() }
            .padding(.horizontal, 30).padding(.vertical, 24)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
    }
}

/// Polls `work` every `interval` seconds while the view is on screen.
struct Refresher: ViewModifier {
    let id: String
    let interval: () -> Double
    let work: () async -> Void
    func body(content: Content) -> some View {
        content.task(id: id) {
            while !Task.isCancelled {
                await work()
                try? await Task.sleep(for: .seconds(interval()))
            }
        }
    }
}

extension View {
    func refreshing(id: String, every interval: @escaping () -> Double, _ work: @escaping () async -> Void) -> some View {
        modifier(Refresher(id: id, interval: interval, work: work))
    }
}

// MARK: - Motion

/// Counts a number up from zero when it appears ("21", "+8", ".750", "2nd").
struct CountUpText: View {
    let text: String
    @State private var progress: Double = Snapshot.enabled ? 1 : 0

    private var parts: (prefix: String, number: Double, decimals: Int, suffix: String)? {
        guard let start = text.firstIndex(where: { $0.isNumber || $0 == "." }) else { return nil }
        var end = start
        while end < text.endIndex, text[end].isNumber || text[end] == "." { end = text.index(after: end) }
        let num = String(text[start..<end])
        guard let v = Double(num) else { return nil }
        let decimals = num.contains(".") ? num.split(separator: ".", omittingEmptySubsequences: false).last?.count ?? 0 : 0
        return (String(text[..<start]), v, decimals, String(text[end...]))
    }

    var body: some View {
        Group {
            if let p = parts {
                Text("").modifier(NumberTicker(value: p.number * progress, decimals: p.decimals, prefix: p.prefix, suffix: p.suffix, leadingDot: text.contains(".") && p.prefix.isEmpty && text.hasPrefix(".")))
            } else {
                Text(text)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.0).delay(0.15)) { progress = 1 } }
    }
}

struct NumberTicker: AnimatableModifier {
    var value: Double
    let decimals: Int
    let prefix: String
    let suffix: String
    let leadingDot: Bool
    var animatableData: Double { get { value } set { value = newValue } }
    func body(content: Content) -> some View {
        var s = String(format: "%.\(decimals)f", value)
        if leadingDot, s.hasPrefix("0.") { s.removeFirst() }
        return Text(prefix + s + suffix).monospacedDigit()
    }
}

/// Subtle 3D tilt that follows the pointer.
struct TiltModifier: ViewModifier {
    var amount: Double = 5
    @State private var rx = 0.0
    @State private var ry = 0.0
    @State private var size: CGSize = .zero
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
            .rotation3DEffect(.degrees(rx), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(ry), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    guard size.width > 0 else { return }
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                        ry = (p.x / size.width - 0.5) * amount
                        rx = -(p.y / size.height - 0.5) * amount
                    }
                case .ended:
                    withAnimation(AQ.spring) { rx = 0; ry = 0 }
                }
            }
    }
}

extension View {
    func tilt(_ amount: Double = 5) -> some View { modifier(TiltModifier(amount: amount)) }
    func shimmer() -> some View { modifier(Shimmer()) }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: phase * g.size.width * 1.6)
                }
                .clipped()
            }
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

/// Placeholder cards that shimmer while data loads.
struct SkeletonPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 8).fill(AQ.fill).frame(width: 180, height: 22).shimmer()
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(AQ.fill).frame(height: 170).shimmer()
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AQ.fill).frame(height: 84).shimmer() }
            }
            HStack(spacing: 18) {
                ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AQ.fill).frame(height: 260).shimmer() }
            }
        }
        .transition(.opacity)
    }
}
