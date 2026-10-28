import SwiftUI
import ImageIO

extension Color {
    init(hex: String?, fallback: Color = .gray) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { self = fallback; return }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { self = fallback; return }
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }

    /// Team colours are sometimes near-black or near-white; nudge them into a usable hero range.
    static func team(_ hex: String?, alt: String? = nil, fallback: Color = Color(hex: "3A3A3C")) -> Color {
        func lum(_ h: String?) -> Double? {
            guard var s = h, s.count >= 6 else { return nil }
            if s.hasPrefix("#") { s.removeFirst() }
            guard let v = UInt32(s, radix: 16) else { return nil }
            let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        if let l = lum(hex), l > 0.08, l < 0.85 { return Color(hex: hex) }
        if let l = lum(alt), l > 0.08, l < 0.85 { return Color(hex: alt) }
        if let l = lum(hex), l <= 0.08 { return Color(hex: "2C2C2E") }
        return fallback
    }
}

enum Thumb {
    static func cgImage(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func download(_ url: URL, maxPixel: Int) async -> CGImage? {
        guard let (data, resp) = try? await ESPN.session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return cgImage(data, maxPixel: maxPixel)
    }
}

/// Subtle line-art of each sport's playing surface, used behind heroes and tiles.
struct SportPattern: View {
    let kind: PatternKind
    var color: Color = .white
    var opacity: Double = 0.10
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let s = GraphicsContext.Shading.color(color.opacity(opacity))
            func stroke(_ p: Path, _ lw: CGFloat? = nil) { ctx.stroke(p, with: s, lineWidth: lw ?? lineWidth) }
            func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
            switch kind {
            case .pitch, .lacrosse:
                stroke(Path(CGRect(x: w * 0.04, y: h * 0.08, width: w * 0.92, height: h * 0.84)))
                stroke(Path { p in p.move(to: CGPoint(x: w / 2, y: h * 0.08)); p.addLine(to: CGPoint(x: w / 2, y: h * 0.92)) })
                stroke(circle(CGPoint(x: w / 2, y: h / 2), h * 0.18))
                stroke(Path(CGRect(x: w * 0.04, y: h * 0.28, width: w * 0.12, height: h * 0.44)))
                stroke(Path(CGRect(x: w * 0.84, y: h * 0.28, width: w * 0.12, height: h * 0.44)))
            case .court:
                stroke(Path(CGRect(x: w * 0.04, y: h * 0.08, width: w * 0.92, height: h * 0.84)))
                stroke(Path { p in p.move(to: CGPoint(x: w / 2, y: h * 0.08)); p.addLine(to: CGPoint(x: w / 2, y: h * 0.92)) })
                stroke(circle(CGPoint(x: w / 2, y: h / 2), h * 0.14))
                for x in [w * 0.04, w * 0.96] {
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: x, y: h / 2), radius: h * 0.38,
                               startAngle: .degrees(x < w / 2 ? -90 : 90), endAngle: .degrees(x < w / 2 ? 90 : 270), clockwise: false)
                    stroke(arc)
                    stroke(Path(CGRect(x: x < w / 2 ? x : x - w * 0.14, y: h * 0.36, width: w * 0.14, height: h * 0.28)))
                }
            case .gridiron:
                for i in 0...10 {
                    let x = w * (0.04 + 0.092 * CGFloat(i))
                    stroke(Path { p in p.move(to: CGPoint(x: x, y: h * 0.06)); p.addLine(to: CGPoint(x: x, y: h * 0.94)) },
                           i % 5 == 0 ? lineWidth * 1.6 : lineWidth)
                }
            case .diamond:
                let c = CGPoint(x: w * 0.5, y: h * 0.62)
                let r = h * 0.42
                stroke(Path { p in
                    p.move(to: CGPoint(x: c.x, y: c.y + r)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                    p.addLine(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x - r, y: c.y)); p.closeSubpath()
                })
                stroke(circle(c, h * 0.06))
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.x, y: c.y + r), radius: r * 2.1, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
                stroke(arc)
            case .rink:
                stroke(Path(roundedRect: CGRect(x: w * 0.04, y: h * 0.08, width: w * 0.92, height: h * 0.84), cornerRadius: h * 0.25))
                stroke(Path { p in p.move(to: CGPoint(x: w / 2, y: h * 0.08)); p.addLine(to: CGPoint(x: w / 2, y: h * 0.92)) }, lineWidth * 2)
                for x in [w * 0.33, w * 0.67] { stroke(Path { p in p.move(to: CGPoint(x: x, y: h * 0.08)); p.addLine(to: CGPoint(x: x, y: h * 0.92)) }) }
                stroke(circle(CGPoint(x: w / 2, y: h / 2), h * 0.14))
                for x in [w * 0.18, w * 0.82] { for y in [h * 0.32, h * 0.68] { stroke(circle(CGPoint(x: x, y: y), h * 0.1)) } }
            case .rugby:
                for i in 0...6 {
                    let x = w * (0.06 + 0.147 * CGFloat(i))
                    stroke(Path { p in p.move(to: CGPoint(x: x, y: h * 0.06)); p.addLine(to: CGPoint(x: x, y: h * 0.94)) })
                }
                for x in [w * 0.06, w * 0.94] {
                    stroke(Path { p in
                        p.move(to: CGPoint(x: x - 10, y: h * 0.3)); p.addLine(to: CGPoint(x: x - 10, y: h * 0.7))
                        p.move(to: CGPoint(x: x + 10, y: h * 0.3)); p.addLine(to: CGPoint(x: x + 10, y: h * 0.7))
                    }, lineWidth * 1.5)
                }
            case .track:
                let cell = max(h / 6, 14)
                var y: CGFloat = 0
                var row = 0
                while y < h {
                    var x: CGFloat = row % 2 == 0 ? 0 : cell
                    while x < w {
                        if x > w * 0.55 { ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: s) }
                        x += cell * 2
                    }
                    y += cell; row += 1
                }
                for i in 0..<3 {
                    var p = Path()
                    p.move(to: CGPoint(x: -20, y: h * (0.75 - 0.12 * CGFloat(i))))
                    p.addCurve(to: CGPoint(x: w * 0.6, y: h * (0.2 - 0.08 * CGFloat(i))),
                               control1: CGPoint(x: w * 0.25, y: h * 0.9), control2: CGPoint(x: w * 0.35, y: 0))
                    stroke(p)
                }
            case .golf:
                for i in 1...6 {
                    let r = CGFloat(i) * h * 0.13
                    var p = Path()
                    p.addEllipse(in: CGRect(x: w * 0.72 - r * 1.4, y: h * 0.5 - r, width: r * 2.8, height: r * 2))
                    stroke(p)
                }
                stroke(Path { p in p.move(to: CGPoint(x: w * 0.72, y: h * 0.5)); p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.12)) }, lineWidth * 1.5)
                ctx.fill(Path { p in
                    p.move(to: CGPoint(x: w * 0.72, y: h * 0.12)); p.addLine(to: CGPoint(x: w * 0.72 + h * 0.16, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.24)); p.closeSubpath()
                }, with: s)
            case .tennis:
                stroke(Path(CGRect(x: w * 0.04, y: h * 0.1, width: w * 0.92, height: h * 0.8)))
                stroke(Path(CGRect(x: w * 0.04, y: h * 0.2, width: w * 0.92, height: h * 0.6)))
                stroke(Path { p in
                    p.move(to: CGPoint(x: w / 2, y: h * 0.06)); p.addLine(to: CGPoint(x: w / 2, y: h * 0.94))
                    p.move(to: CGPoint(x: w * 0.25, y: h / 2)); p.addLine(to: CGPoint(x: w * 0.75, y: h / 2))
                    p.move(to: CGPoint(x: w * 0.25, y: h * 0.2)); p.addLine(to: CGPoint(x: w * 0.25, y: h * 0.8))
                    p.move(to: CGPoint(x: w * 0.75, y: h * 0.2)); p.addLine(to: CGPoint(x: w * 0.75, y: h * 0.8))
                }, lineWidth * 1.4)
            case .octagon:
                for scale in [0.42, 0.3] {
                    let c = CGPoint(x: w * 0.72, y: h / 2)
                    let r = h * scale * 2
                    stroke(Path { p in
                        for i in 0..<8 {
                            let a = Double(i) * .pi / 4 + .pi / 8
                            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                        p.closeSubpath()
                    }, scale > 0.4 ? lineWidth * 1.6 : lineWidth)
                }
            case .cricket:
                stroke(Path(ellipseIn: CGRect(x: w * 0.1, y: -h * 0.2, width: w * 0.8, height: h * 1.4)))
                stroke(Path(CGRect(x: w * 0.44, y: h * 0.18, width: w * 0.12, height: h * 0.64)))
                for y in [h * 0.24, h * 0.76] {
                    stroke(Path { p in p.move(to: CGPoint(x: w * 0.42, y: y)); p.addLine(to: CGPoint(x: w * 0.58, y: y)) })
                }
            }
        }
        .allowsHitTesting(false)
    }
}
