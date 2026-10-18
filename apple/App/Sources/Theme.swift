import SwiftUI

/// Visual tokens for a calculator skin. Phase 1 (Figma) adds the other named themes.
struct Theme: Sendable {
    var displayFont: Font
    var background: Color
    var resultColor: Color
    var secondaryText: Color
    var keyColor: Color
    var keyText: Color
    var functionKeyColor: Color
    var operatorColor: Color
    var equalsColor: Color
    var keyCornerRadius: CGFloat

    static func graphite(displaySize: CGFloat = 88) -> Theme { Theme(
        displayFont: .system(size: displaySize, weight: .bold, design: .rounded).width(.condensed),
        background: Color(white: 0.08),
        resultColor: .white,
        secondaryText: Color(white: 0.6),
        keyColor: Color(white: 0.18),
        keyText: .white,
        functionKeyColor: Color(white: 0.32),
        operatorColor: Color(red: 1.0, green: 0.55, blue: 0.1),
        equalsColor: Color(red: 1.0, green: 0.35, blue: 0.6),
        keyCornerRadius: 22
    ) }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .graphite()
}
