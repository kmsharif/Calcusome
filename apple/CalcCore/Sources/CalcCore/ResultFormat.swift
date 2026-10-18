/// Display formats for a canonical result. Display-only: history keeps the canonical decimal.
public enum ResultFormat: String, CaseIterable, Sendable {
    case decimal, fraction, hex, binary, octal

    /// Larger denominators read worse than the decimal they replace.
    // ponytail: fixed cap; make it a setting if people ask for 1/1048576-style fractions.
    static let maxDenominator: UInt128 = 1_000_000

    public var badge: String {
        switch self {
        case .decimal: "DEC"
        case .fraction: "FRAC"
        case .hex: "HEX"
        case .binary: "BIN"
        case .octal: "OCT"
        }
    }

    public var name: String {
        switch self {
        case .decimal: "Decimal"
        case .fraction: "Fraction"
        case .hex: "Hexadecimal"
        case .binary: "Binary"
        case .octal: "Octal"
        }
    }

    /// `canonical` in this format with an ASCII "-" for negatives, or nil when it can't be shown
    /// (a fraction of an integer, a non-integer in another base). Decimal always returns nil:
    /// the caller already has the canonical text.
    public func render(_ canonical: String) -> String? {
        let negative = canonical.hasPrefix("-")
        let body = negative ? canonical.dropFirst() : Substring(canonical)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts[0], fraction = parts.count > 1 ? parts[1] : ""
        let text: String?
        switch self {
        case .decimal: return nil
        case .fraction: text = Self.fraction(whole: whole, fraction: fraction, canonical: String(body))
        case .hex: text = fraction.isEmpty ? UInt128(whole).map { String($0, radix: 16, uppercase: true) } : nil
        case .octal: text = fraction.isEmpty ? UInt128(whole).map { String($0, radix: 8) } : nil
        case .binary: text = fraction.isEmpty ? UInt128(whole).map { Self.nibbles(String($0, radix: 2)) } : nil
        }
        return text.map { negative ? "-" + $0 : $0 }
    }

    /// First continued-fraction convergent p/q of the exact decimal that rounds back to it at 34 digits,
    /// so 0.333…3 (34 digits) is 1/3. Mixed form: "1 1/3".
    private static func fraction(whole: Substring, fraction: Substring, canonical: String) -> String? {
        guard !fraction.isEmpty, fraction.count <= 38, var n = UInt128(whole + fraction) else { return nil }
        var d: UInt128 = 1
        for _ in 0..<fraction.count { d *= 10 }  // 10^38 still fits in UInt128
        var (p, pPrev): (UInt128, UInt128) = (1, 0)
        var (q, qPrev): (UInt128, UInt128) = (0, 1)
        while d != 0 {
            let a = n / d
            (n, d) = (d, n % d)
            (p, pPrev) = (a * p + pPrev, p)  // convergents never exceed the reduced N/D, so no overflow
            (q, qPrev) = (a * q + qPrev, q)
            if q > maxDenominator { return nil }
            if let x = ExactDecimal(literal: String(p)), let y = ExactDecimal(literal: String(q)),
               (x / y).canonical == canonical {
                let units = p / q, rest = p % q
                return units > 0 ? "\(units) \(rest)/\(q)" : "\(rest)/\(q)"
            }
        }
        return nil
    }

    private static func nibbles(_ bits: String) -> String {
        let padded = String(repeating: "0", count: (4 - bits.count % 4) % 4) + bits
        var groups: [Substring] = []
        var i = padded.startIndex
        while i < padded.endIndex {
            let j = padded.index(i, offsetBy: 4)
            groups.append(padded[i..<j])
            i = j
        }
        return groups.joined(separator: " ")
    }
}
