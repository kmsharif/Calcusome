public enum CalcError: String, Error, Equatable, Sendable {
    case syntax
    case divideByZero = "divide_by_zero"
    case overflow
}

/// Evaluates canonical expressions (`500×64`, `200+10%`) to a canonical result. Grammar:
///
///     expr    := term (('+' | '−') term)*     a ± p%  →  a ± a×p/100
///     term    := factor (('×' | '÷') factor)*
///     factor  := '−' factor | primary '%'?    p%  →  p/100
///     primary := number | '(' expr ')'
///
/// Every literal and operation is rounded to 34 significant digits, half-even (see `ExactDecimal`).
public enum Engine {
    public static let significantDigits = ExactDecimal.precision

    public static func evaluate(_ canonical: String) throws(CalcError) -> String {
        var parser = Parser(chars: Array(canonical))
        let value = try parser.expr()
        guard parser.pos == parser.chars.count else { throw .syntax }
        return value.canonical
    }

    fileprivate static func checked(_ d: ExactDecimal) throws(CalcError) -> ExactDecimal {
        if d.top >= 34 { throw .overflow }  // |d| >= 1e34
        return d
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        mutating func eat(_ c: Character) -> Bool {
            guard pos < chars.count, chars[pos] == c else { return false }
            pos += 1
            return true
        }

        mutating func expr() throws(CalcError) -> ExactDecimal {
            var value = try term().value
            while true {
                let negate: Bool
                if eat("+") { negate = false } else if eat("−") { negate = true } else { return value }
                let (rhs, isPercent) = try term()
                let delta = isPercent ? try checked(value * rhs) : rhs
                value = try checked(negate ? value - delta : value + delta)
            }
        }

        mutating func term() throws(CalcError) -> (value: ExactDecimal, isPercent: Bool) {
            var (value, isPercent) = try factor()
            while true {
                if eat("×") {
                    value = try checked(value * factor().value)
                } else if eat("÷") {
                    let divisor = try factor().value
                    if divisor.isZero { throw .divideByZero }
                    value = try checked(value / divisor)
                } else {
                    return (value, isPercent)
                }
                isPercent = false
            }
        }

        mutating func factor() throws(CalcError) -> (value: ExactDecimal, isPercent: Bool) {
            if eat("−") { return (-(try factor().value), false) }
            let value = try primary()
            return eat("%") ? (value.percent, true) : (value, false)
        }

        mutating func primary() throws(CalcError) -> ExactDecimal {
            if eat("(") {
                let value = try expr()
                guard eat(")") else { throw .syntax }
                return value
            }
            let start = pos
            while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
            guard let d = ExactDecimal(literal: chars[start..<pos].map(String.init).joined()) else { throw .syntax }
            return try checked(d)
        }
    }
}
