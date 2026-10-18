import Foundation

/// The shared precision rule: 34 significant digits, round half-even
/// (same as Java `MathContext.DECIMAL128`, which the Android engine uses).
public enum DecimalRounding {
    public static let significantDigits = 34

    public static func round34(_ d: Decimal) -> Decimal {
        if d.isZero { return 0 }
        // ponytail: Swift Decimal already rounds at 38 digits, so a value that lands exactly on a
        // half at digit 35 after that can double-round; fine unless a spec case proves otherwise.
        let magnitude = orderOfMagnitude(d)
        var input = d
        var output = Decimal()
        NSDecimalRound(&output, &input, significantDigits - 1 - magnitude, .bankers)
        return output
    }

    /// Plain notation, no trailing zeros, never "-0".
    public static func canonical(_ d: Decimal) -> String {
        d.isZero ? "0" : d.description
    }

    /// k such that 10^k <= |d| < 10^(k+1).
    private static func orderOfMagnitude(_ d: Decimal) -> Int {
        let plain = abs(d).description
        guard plain.hasPrefix("0.") else {
            return (plain.firstIndex(of: ".").map { plain.distance(from: plain.startIndex, to: $0) } ?? plain.count) - 1
        }
        let zeros = plain.dropFirst(2).prefix { $0 == "0" }.count
        return -(zeros + 1)
    }
}
