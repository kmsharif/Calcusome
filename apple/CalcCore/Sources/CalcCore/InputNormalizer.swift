import Foundation

/// Converts what a person types or pastes into a canonical expression, and canonical text back
/// into their locale for display.
public enum InputNormalizer {
    private static let operatorAliases: [Character: Character] = [
        "*": "×", "x": "×", "X": "×", "/": "÷", "-": "−", "–": "−", "—": "−",
    ]

    /// Zero code points of the non-ASCII digit sets we accept: Arabic-Indic, Extended Arabic-Indic, Bengali.
    private static let digitZeros: [UInt32] = [0x0660, 0x06F0, 0x09E6]

    public static func normalize(_ raw: String, locale: Locale) -> String {
        let grouping = locale.groupingSeparator ?? ""
        let decimal = locale.decimalSeparator ?? "."
        var s = String(raw.unicodeScalars.map(asciiDigit).filter { !$0.properties.isWhitespace }.map(Character.init))
        // Grouping before decimal: in de_DE "." is grouping and "," becomes the point.
        if !grouping.isEmpty, grouping != decimal { s = s.replacingOccurrences(of: grouping, with: "") }
        if decimal != "." { s = s.replacingOccurrences(of: decimal, with: ".") }
        return String(s.map { operatorAliases[$0] ?? $0 })
    }

    public static func display(result canonical: String, locale: Locale, grouping: Bool = true) -> String {
        guard let d = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")) else { return canonical }
        return d.formatted(.number.locale(locale).precision(.significantDigits(1...Engine.significantDigits))
            .grouping(grouping ? .automatic : .never))
    }

    public static func display(expression canonical: String, locale: Locale) -> String {
        canonical.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    static func asciiDigit(_ u: Unicode.Scalar) -> Unicode.Scalar {
        for zero in digitZeros where (zero...zero + 9).contains(u.value) {
            return Unicode.Scalar(0x30 + u.value - zero)!
        }
        return u
    }
}
