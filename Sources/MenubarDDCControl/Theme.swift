import AppKit
import SwiftUI

/// Rosé Pine (https://rosepinetheme.com, MIT): Moon when macOS is dark, Dawn when it is light.
/// Colours resolve at draw time from the view's appearance, so switching macOS's appearance
/// re-themes the app immediately.
enum Theme {
    struct Palette: Sendable {
        var base, surface, overlay, muted, subtle, text, love, gold, rose, pine, foam, iris: UInt32
    }

    // From rose-pine/palette, palette.json.
    static let moon = Palette(base: 0x232136, surface: 0x2A273F, overlay: 0x393552, muted: 0x6E6A86, subtle: 0x908CAA,
                              text: 0xE0DEF4, love: 0xEB6F92, gold: 0xF6C177, rose: 0xEA9A97, pine: 0x3E8FB0,
                              foam: 0x9CCFD8, iris: 0xC4A7E7)
    static let dawn = Palette(base: 0xFAF4ED, surface: 0xFFFAF3, overlay: 0xF2E9E1, muted: 0x9893A5, subtle: 0x797593,
                              text: 0x464261, love: 0xB4637A, gold: 0xEA9D34, rose: 0xD7827E, pine: 0x286983,
                              foam: 0x56949F, iris: 0x907AA9)

    static let base = color(\.base)
    static let surface = color(\.surface)
    static let overlay = color(\.overlay)
    /// Decoration only (tick marks, dashes): below text contrast in both variants.
    static let muted = color(\.muted)
    static let text = color(\.text)
    /// Secondary text: Rosé Pine's `subtle`, nudged 20 % toward `text` so captions reach 4.5:1
    /// on `surface` (Moon 5.4:1, Dawn 4.9:1; plain `subtle` is 4.5 and 4.2).
    static let secondaryText = color { palette, _ in mix(palette.subtle, palette.text, 0.2) }
    static let love = color(\.love)
    /// Warning icons. Dawn's gold is 2.2:1 on `surface`, so warning *text* stays `text`.
    static let gold = color(\.gold)
    static let pine = color(\.pine)
    static let foam = color(\.foam)
    static let iris = color(\.iris)
    /// Accent for sliders, checkboxes and toggles.
    static let accent = iris
    /// Links: foam on Moon (8.4:1), pine on Dawn (5.9:1). Iris is too faint for text on Dawn.
    static let link = color { palette, dark in dark ? palette.foam : palette.pine }

    // MARK: Resolution

    private static func color(_ key: KeyPath<Palette, UInt32>) -> Color {
        let (dark, light) = (moon[keyPath: key], dawn[keyPath: key])
        return color { _, isDark in isDark ? dark : light }
    }

    /// A colour that picks its value from Moon or Dawn each time it is drawn.
    private static func color(_ pick: @escaping @Sendable (Palette, _ dark: Bool) -> UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: pick(dark ? moon : dawn, dark))
        })
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
        var out: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            out |= UInt32((channel(a, shift) * (1 - t) + channel(b, shift) * t).rounded()) << shift
        }
        return out
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// A form section on Rosé Pine's `surface`, for grouped forms whose own background is hidden.
struct ThemedSection<Content: View, Header: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var header: () -> Header
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Section {
            content()
        } header: {
            header().foregroundStyle(Theme.text)
        } footer: {
            footer().foregroundStyle(Theme.secondaryText)
        }
        .listRowBackground(Theme.surface)
    }
}

extension ThemedSection where Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder header: @escaping () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension ThemedSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension ThemedSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension ThemedSection where Header == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension View {
    /// Rosé Pine behind a grouped form, with its accent colour.
    func themedForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.base)
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
    }
}
