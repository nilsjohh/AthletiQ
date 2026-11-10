import SwiftUI

// Thin layer over the few places where macOS (AppKit) and iOS (UIKit) differ.

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

extension NSImage {
    convenience init(cg: CGImage) { self.init(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
}
extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
extension Color {
    init(platformColor: PlatformColor) { self.init(nsColor: platformColor) }
}
func dynamicColor(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
    NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
}
#else
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

extension UIImage {
    convenience init(cg: CGImage) { self.init(cgImage: cg) }
}
extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
extension Color {
    init(platformColor: PlatformColor) { self.init(uiColor: platformColor) }
}
func dynamicColor(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
    UIColor { $0.userInterfaceStyle == .dark ? dark : light }
}
#endif

/// True on iPhone-width layouts (and in narrow windows on iPad); false on Mac.
private struct CompactKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isCompact: Bool {
        get { self[CompactKey.self] }
        set { self[CompactKey.self] = newValue }
    }
}

extension View {
    /// Pointer cursor on Mac; no-op on iPhone.
    @ViewBuilder func linkPointer() -> some View {
        #if os(macOS)
        self.pointerStyle(.link)
        #else
        self
        #endif
    }

    /// Light tap feedback on iPhone.
    func tapFeedback<T: Equatable>(_ trigger: T) -> some View {
        self.sensoryFeedback(.impact(weight: .light), trigger: trigger)
    }
}

/// Adaptive grid columns that never ask for more width than a phone has.
func adaptiveColumns(_ minimum: CGFloat, compact: Bool, spacing: CGFloat = 14, alignment: Alignment = .center) -> [GridItem] {
    [GridItem(.adaptive(minimum: compact ? min(minimum, 300) : minimum), spacing: spacing, alignment: alignment)]
}

enum Device {
    /// iPhone layout (portrait phone). Settable so previews can render the phone layout on a Mac.
    nonisolated(unsafe) static var isPhone: Bool = {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }()
}

/// Pick a value for Mac/iPad (first) or iPhone (second).
func ph<T>(_ regular: T, _ phone: T) -> T { Device.isPhone ? phone : regular }

/// Grid minimum width that still fits on a phone.
func gm(_ n: CGFloat) -> CGFloat { Device.isPhone ? min(n, 300) : n }

/// HStack on Mac, VStack on iPhone.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 18
    var alignment: VerticalAlignment = .top
    @ViewBuilder let content: () -> Content
    var body: some View {
        if Device.isPhone {
            VStack(alignment: .leading, spacing: spacing) { content() }
        } else {
            HStack(alignment: alignment, spacing: spacing) { content() }
        }
    }
}

/// Icon + title on Mac, icon only on iPhone.
struct PhoneIconOnly: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        if Device.isPhone { configuration.icon } else { Label(configuration) }
    }
}
