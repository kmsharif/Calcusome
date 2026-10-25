import SwiftUI

/// Visual tokens for a calculator skin. Colors are placeholders until the Phase 1 (Figma) tokens land.
struct Theme: Identifiable, Sendable {
    var id: String
    var name: String
    var colorScheme: ColorScheme
    var fontDesign: Font.Design
    var background: Color
    var resultColor: Color
    var secondaryText: Color
    var keyColor: Color
    var keyText: Color
    var functionKeyColor: Color
    var operatorColor: Color
    var equalsColor: Color
    var keyCornerRadius: CGFloat
    var displaySize: CGFloat = 88
    var keySize: CGFloat = 30

    func displayFont(scale: CGFloat = 1) -> Font { .system(size: displaySize * scale, weight: .bold, design: fontDesign).width(.condensed) }
    func keyFont(scale: CGFloat = 1) -> Font { .system(size: keySize * scale, weight: .medium, design: fontDesign) }

    /// This theme at a size setting; `display` is the medium display size for the surface.
    func sized(_ size: DisplaySize, display: CGFloat = 88) -> Theme {
        var t = self
        t.displaySize = display * size.scale
        t.keySize = 30 * size.scale
        return t
    }

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .graphite }

    static let all: [Theme] = [graphite, paper, midnight, terminal, bloom]

    static let graphite = Theme(
        id: "graphite", name: "Graphite", colorScheme: .dark, fontDesign: .rounded,
        background: Color(white: 0.08),
        resultColor: .white,
        secondaryText: Color(white: 0.6),
        keyColor: Color(white: 0.18),
        keyText: .white,
        functionKeyColor: Color(white: 0.32),
        operatorColor: Color(red: 1.0, green: 0.55, blue: 0.1),
        equalsColor: Color(red: 1.0, green: 0.35, blue: 0.6),
        keyCornerRadius: 22
    )

    static let paper = Theme(
        id: "paper", name: "Paper", colorScheme: .light, fontDesign: .default,
        background: Color(white: 0.96),
        resultColor: Color(white: 0.08),
        secondaryText: Color(white: 0.42),
        keyColor: .white,
        keyText: Color(white: 0.08),
        functionKeyColor: Color(white: 0.86),
        operatorColor: Color(red: 0.96, green: 0.6, blue: 0.2),
        equalsColor: Color(red: 0.55, green: 0.78, blue: 1.0),
        keyCornerRadius: 14
    )

    static let midnight = Theme(
        id: "midnight", name: "Midnight", colorScheme: .dark, fontDesign: .rounded,
        background: Color(red: 0.04, green: 0.06, blue: 0.14),
        resultColor: .white,
        secondaryText: Color(red: 0.55, green: 0.62, blue: 0.78),
        keyColor: Color(red: 0.1, green: 0.14, blue: 0.27),
        keyText: .white,
        functionKeyColor: Color(red: 0.18, green: 0.23, blue: 0.4),
        operatorColor: Color(red: 0.0, green: 0.5, blue: 0.72),
        equalsColor: Color(red: 0.42, green: 0.36, blue: 0.95),
        keyCornerRadius: 18
    )

    static let terminal = Theme(
        id: "terminal", name: "Terminal", colorScheme: .dark, fontDesign: .monospaced,
        background: .black,
        resultColor: Color(red: 0.25, green: 1.0, blue: 0.45),
        secondaryText: Color(red: 0.15, green: 0.6, blue: 0.3),
        keyColor: Color(red: 0.05, green: 0.1, blue: 0.06),
        keyText: Color(red: 0.25, green: 1.0, blue: 0.45),
        functionKeyColor: Color(red: 0.08, green: 0.18, blue: 0.1),
        operatorColor: Color(red: 0.1, green: 0.32, blue: 0.15),
        equalsColor: Color(red: 0.12, green: 0.45, blue: 0.2),
        keyCornerRadius: 4
    )

    static let bloom = Theme(
        id: "bloom", name: "Bloom", colorScheme: .light, fontDesign: .rounded,
        background: Color(red: 1.0, green: 0.95, blue: 0.96),
        resultColor: Color(red: 0.3, green: 0.1, blue: 0.25),
        secondaryText: Color(red: 0.58, green: 0.42, blue: 0.52),
        keyColor: .white,
        keyText: Color(red: 0.3, green: 0.1, blue: 0.25),
        functionKeyColor: Color(red: 0.98, green: 0.85, blue: 0.9),
        operatorColor: Color(red: 1.0, green: 0.7, blue: 0.8),
        equalsColor: Color(red: 0.76, green: 0.7, blue: 1.0),
        keyCornerRadius: 30
    )
}

enum DisplaySize: String, CaseIterable {
    case small, medium, large

    var name: String { rawValue.capitalized }

    var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.25
        }
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .graphite
}

/// Applies the chosen theme and size, and matches the window's light/dark appearance to it.
private struct Themed: ViewModifier {
    var display: CGFloat
    @AppStorage(Pref.theme) private var themeID = Theme.graphite.id
    @AppStorage(Pref.size) private var size = DisplaySize.medium

    func body(content: Content) -> some View {
        let theme = Theme.named(themeID).sized(size, display: display)
        content
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
    }
}

extension View {
    func themed(display: CGFloat = 88) -> some View { modifier(Themed(display: display)) }
}
