import Foundation

public enum CalcError: String, Error, Equatable, Sendable {
    case syntax
    case divideByZero = "divide_by_zero"
    case overflow
}

/// Evaluates canonical expressions (`500×64`, `200+10%`). Grammar:
///
///     expr    := term (('+' | '−') term)*     a ± p%  →  a ± a×p/100
///     term    := factor (('×' | '÷') factor)*
///     factor  := '−' factor | primary '%'?    p%  →  p/100
///     primary := number | '(' expr ')'
public enum Engine {
    public static func evaluate(_ canonical: String) throws(CalcError) -> Decimal {
        var parser = Parser(chars: Array(canonical))
        let value = try parser.expr()
        guard parser.pos == parser.chars.count else { throw .syntax }
        return value
    }

    private static let limit = Decimal(sign: .plus, exponent: 34, significand: 1)

    fileprivate static func checked(_ d: Decimal) throws(CalcError) -> Decimal {
        let r = DecimalRounding.round34(d)
        if abs(r) >= limit { throw .overflow }
        return r
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        mutating func eat(_ c: Character) -> Bool {
            guard pos < chars.count, chars[pos] == c else { return false }
            pos += 1
            return true
        }

        mutating func expr() throws(CalcError) -> Decimal {
            var value = try term().value
            while true {
                let sign: Decimal
                if eat("+") { sign = 1 } else if eat("−") { sign = -1 } else { return value }
                let (rhs, isPercent) = try term()
                let delta = isPercent ? try checked(value * rhs) : rhs
                value = try checked(value + sign * delta)
            }
        }

        mutating func term() throws(CalcError) -> (value: Decimal, isPercent: Bool) {
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

        mutating func factor() throws(CalcError) -> (value: Decimal, isPercent: Bool) {
            if eat("−") { return (try checked(-factor().value), false) }
            let value = try primary()
            return eat("%") ? (try checked(value / 100), true) : (value, false)
        }

        mutating func primary() throws(CalcError) -> Decimal {
            if eat("(") {
                let value = try expr()
                guard eat(")") else { throw .syntax }
                return value
            }
            let start = pos
            while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
            let text = String(chars[start..<pos])
            guard !text.isEmpty,
                  text.filter({ $0 == "." }).count <= 1,
                  text.first != ".", text.last != ".",
                  let d = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
            else { throw .syntax }
            return try checked(d)
        }
    }
}
