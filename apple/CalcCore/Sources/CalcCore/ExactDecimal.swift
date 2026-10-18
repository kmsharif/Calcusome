/// sign × coefficient × 10^exponent, with the coefficient as decimal digits.
///
/// Foundation's `Decimal` truncates when aligning operands and rounds division at 38 digits,
/// so it can't round each operation correctly. This type computes exactly, then rounds to
/// 34 significant digits half-even, which matches Java `MathContext.DECIMAL128` on Android.
struct ExactDecimal: Equatable {
    static let precision = 34

    private(set) var negative = false
    /// Least significant first, no high zeros; empty means zero.
    private(set) var digits: [UInt8] = []
    private(set) var exponent = 0

    static let zero = ExactDecimal()

    var isZero: Bool { digits.isEmpty }

    /// Position of the leading digit: 10^top <= |self| < 10^(top+1).
    var top: Int { exponent + digits.count - 1 }

    /// Parses `digits[.digits]`, also `.5` and `5.`; nil for anything else.
    init?(literal: some StringProtocol) {
        var coefficient: [UInt8] = []
        var fraction = 0
        var seenPoint = false
        for c in literal {
            if c == "." {
                guard !seenPoint else { return nil }
                seenPoint = true
            } else if let d = c.wholeNumberValue, c.isASCII {
                coefficient.append(UInt8(d))
                if seenPoint { fraction += 1 }
            } else {
                return nil
            }
        }
        guard !coefficient.isEmpty else { return nil }
        self.init(negative: false, digits: coefficient.reversed(), exponent: -fraction)
    }

    private init() {}

    private init(negative: Bool, digits: [UInt8], exponent: Int, sticky: Bool = false) {
        var digits = digits
        while digits.last == 0 { digits.removeLast() }
        guard !digits.isEmpty else { self = .zero; return }
        self.negative = negative
        self.digits = digits
        self.exponent = exponent
        round(sticky: sticky)
        while self.digits.first == 0 { self.digits.removeFirst(); self.exponent += 1 }
    }

    /// Rounds to `precision` digits, half-even. `sticky` means nonzero digits were already dropped below.
    private mutating func round(sticky: Bool) {
        let drop = digits.count - Self.precision
        guard drop > 0 else { return }
        let first = digits[drop - 1]
        let rest = sticky || digits[..<(drop - 1)].contains { $0 != 0 }
        digits.removeFirst(drop)
        exponent += drop
        let up = first > 5 || (first == 5 && (rest || digits[0] % 2 == 1))
        guard up else { return }
        var i = 0
        while i < digits.count, digits[i] == 9 { digits[i] = 0; i += 1 }
        if i == digits.count { digits.append(1) } else { digits[i] += 1 }
        if digits.count > Self.precision { digits.removeFirst(); exponent += 1 }  // 99…9 → 100…0, dropped digit is 0
    }

    static prefix func - (x: ExactDecimal) -> ExactDecimal {
        var r = x
        if !r.isZero { r.negative.toggle() }
        return r
    }

    static func + (a: ExactDecimal, b: ExactDecimal) -> ExactDecimal {
        if a.isZero { return b }
        if b.isZero { return a }
        // A far smaller operand can't move a 34-digit result: it is under half an ulp even after a borrow.
        if b.top < a.top - precision - 2 { return a }
        if a.top < b.top - precision - 2 { return b }
        let e = min(a.exponent, b.exponent)
        let x = shifted(a.digits, by: a.exponent - e), y = shifted(b.digits, by: b.exponent - e)
        if a.negative == b.negative {
            return ExactDecimal(negative: a.negative, digits: add(x, y), exponent: e)
        }
        return compare(x, y) >= 0
            ? ExactDecimal(negative: a.negative, digits: subtract(x, y), exponent: e)
            : ExactDecimal(negative: b.negative, digits: subtract(y, x), exponent: e)
    }

    static func - (a: ExactDecimal, b: ExactDecimal) -> ExactDecimal { a + -b }

    static func * (a: ExactDecimal, b: ExactDecimal) -> ExactDecimal {
        if a.isZero || b.isZero { return .zero }
        var product = [UInt8](repeating: 0, count: a.digits.count + b.digits.count)
        for (i, x) in a.digits.enumerated() {
            var carry = 0
            for (j, y) in b.digits.enumerated() {
                let t = Int(product[i + j]) + Int(x) * Int(y) + carry
                product[i + j] = UInt8(t % 10)
                carry = t / 10
            }
            product[i + b.digits.count] = UInt8(carry)
        }
        return ExactDecimal(negative: a.negative != b.negative, digits: product, exponent: a.exponent + b.exponent)
    }

    /// Caller guarantees `b` is nonzero.
    static func / (a: ExactDecimal, b: ExactDecimal) -> ExactDecimal {
        if a.isZero { return .zero }
        // Scale the dividend so the integer quotient has at least precision + 2 digits.
        let scale = max(0, precision + 2 + b.digits.count - a.digits.count)
        let numerator = shifted(a.digits, by: scale)
        var quotient: [UInt8] = []
        var remainder: [UInt8] = []
        for digit in numerator.reversed() {
            remainder = trimmed([digit] + remainder)
            var q: UInt8 = 0
            while compare(remainder, b.digits) >= 0 {
                remainder = subtract(remainder, b.digits)
                q += 1
            }
            quotient.append(q)
        }
        return ExactDecimal(negative: a.negative != b.negative, digits: quotient.reversed(),
                            exponent: a.exponent - b.exponent - scale, sticky: !remainder.isEmpty)
    }

    /// Exact divide by 100.
    var percent: ExactDecimal {
        var r = self
        if !r.isZero { r.exponent -= 2 }
        return r
    }

    /// Plain notation, no trailing zeros, "-" for negatives, never "-0".
    var canonical: String {
        if isZero { return "0" }
        let coefficient = String(digits.reversed().map { Character(String($0)) })
        let body: String
        if exponent >= 0 {
            body = coefficient + String(repeating: "0", count: exponent)
        } else {
            let padded = String(repeating: "0", count: max(0, -exponent - coefficient.count + 1)) + coefficient
            let split = padded.index(padded.endIndex, offsetBy: exponent)
            body = padded[..<split] + "." + padded[split...]
        }
        return negative ? "-" + body : body
    }

    // MARK: Digit arrays (least significant first)

    private static func shifted(_ x: [UInt8], by n: Int) -> [UInt8] {
        [UInt8](repeating: 0, count: n) + x
    }

    private static func trimmed(_ x: [UInt8]) -> [UInt8] {
        var x = x
        while x.last == 0 { x.removeLast() }
        return x
    }

    private static func compare(_ x: [UInt8], _ y: [UInt8]) -> Int {
        let x = trimmed(x), y = trimmed(y)
        if x.count != y.count { return x.count < y.count ? -1 : 1 }
        for i in stride(from: x.count - 1, through: 0, by: -1) where x[i] != y[i] {
            return x[i] < y[i] ? -1 : 1
        }
        return 0
    }

    private static func add(_ x: [UInt8], _ y: [UInt8]) -> [UInt8] {
        var r: [UInt8] = []
        var carry: UInt8 = 0
        for i in 0..<max(x.count, y.count) {
            let t = (i < x.count ? x[i] : 0) + (i < y.count ? y[i] : 0) + carry
            r.append(t % 10)
            carry = t / 10
        }
        if carry > 0 { r.append(carry) }
        return r
    }

    /// x - y, where x >= y.
    private static func subtract(_ x: [UInt8], _ y: [UInt8]) -> [UInt8] {
        var r: [UInt8] = []
        var borrow = 0
        for i in 0..<x.count {
            var t = Int(x[i]) - Int(i < y.count ? y[i] : 0) - borrow
            borrow = t < 0 ? 1 : 0
            if t < 0 { t += 10 }
            r.append(UInt8(t))
        }
        return trimmed(r)
    }
}
