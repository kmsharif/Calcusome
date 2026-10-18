import Foundation
import Observation

public enum Key: Hashable, Sendable {
    case digit(Int), decimal, add, subtract, multiply, divide, percent, openParen, closeParen
    case negate, backspace, clear, equals

    var symbol: Character? {
        switch self {
        case .digit(let d): Character(String(d))
        case .decimal: "."
        case .add: "+"
        case .subtract: "−"
        case .multiply: "×"
        case .divide: "÷"
        case .percent: "%"
        case .openParen: "("
        case .closeParen: ")"
        default: nil
        }
    }

    /// Hardware keyboard input. "," is the decimal point only where the locale uses it;
    /// elsewhere it's grouping and ignored, matching how pasted text is read.
    public init?(typed c: Character, locale: Locale = .current) {
        if c.unicodeScalars.count == 1, let scalar = c.unicodeScalars.first,
           case let ascii = InputNormalizer.asciiDigit(scalar), ("0"..."9").contains(ascii) {
            self = .digit(Int(ascii.value) - 0x30)  // Bengali, Arabic-Indic, Persian keyboards too
            return
        }
        switch c {
        case ".": self = .decimal
        case "," where locale.decimalSeparator == ",": self = .decimal
        case "+": self = .add
        case "-", "−": self = .subtract
        case "*", "x", "X", "×": self = .multiply
        case "/", "÷": self = .divide
        case "%": self = .percent
        case "(": self = .openParen
        case ")": self = .closeParen
        case "=", "\r", "\n", "\u{3}": self = .equals  // U+0003 is numpad Enter on Mac
        default: return nil
        }
    }

    var isOperator: Bool { [.add, .subtract, .multiply, .divide, .percent].contains(self) }
}

@MainActor @Observable public final class CalculatorModel {
    public private(set) var expression = ""
    public private(set) var result: String?
    public private(set) var error: CalcError?
    public private(set) var recent: [HistoryEntry] = []

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var lastSaved: String?

    public init(store: HistoryStore, locale: Locale = .current) {
        self.store = store
        self.locale = locale
        refreshRecent()
    }

    public func press(_ key: Key) {
        error = nil
        switch key {
        case .equals: if !expression.isEmpty { evaluate() }
        case .clear: expression = ""; result = nil; lastSaved = nil
        case .backspace: startEditing(); if !expression.isEmpty { expression.removeLast() }
        case .negate:
            if let result { expression = Self.asExpression(result); self.result = nil }  // negate the shown result
            negateLastOperand()
        case .decimal:
            startEditing()
            if !trailingNumber.contains(".") { expression.append(".") }
        default:
            guard let symbol = key.symbol else { return }
            if let result, key.isOperator {
                expression = Self.asExpression(result)  // continue from the result
                self.result = nil
            } else {
                startEditing()
            }
            expression.append(symbol)
        }
    }

    public func paste(_ text: String) {
        expression = InputNormalizer.normalize(text, locale: locale)
        result = nil
        error = nil
    }

    /// Chip tap: append a past result, or start from it right after "=".
    public func reuse(_ entry: HistoryEntry) {
        startEditing()
        if let last = expression.last, last.isNumber || ".)%".contains(last) { expression.append("×") }
        expression += Self.asExpression(entry.result)
        error = nil
    }

    private func evaluate() {
        do {
            let value = try Engine.evaluate(expression)
            result = value
            let isLoneNumber = expression.drop { $0 == "−" }.allSatisfy { $0.isNumber || $0 == "." }
            guard expression != lastSaved, !isLoneNumber else { return }
            guard (try? store.add(expression: expression, result: value)) != nil else { return }
            lastSaved = expression
            refreshRecent()
        } catch {
            self.error = error
        }
    }

    /// Typing after a result starts a new expression.
    private func startEditing() {
        if result != nil { expression = ""; result = nil }
    }

    private var trailingNumber: Substring {
        expression[(expression.lastIndex { !($0.isNumber || $0 == ".") }.map(expression.index(after:)) ?? expression.startIndex)...]
    }

    /// Start of the last operand: a number or a parenthesised group, either optionally followed by %.
    private var trailingOperandStart: Int? {
        let chars = Array(expression)
        var i = chars.count
        if i > 0, chars[i - 1] == "%" { i -= 1 }
        if i > 0, chars[i - 1] == ")" {
            var depth = 0
            repeat {
                i -= 1
                if chars[i] == ")" { depth += 1 } else if chars[i] == "(" { depth -= 1 }
            } while depth > 0 && i > 0
            return depth == 0 ? i : nil
        }
        while i > 0, chars[i - 1].isNumber || chars[i - 1] == "." { i -= 1 }
        return i
    }

    private func negateLastOperand() {
        guard let start = trailingOperandStart else { return }
        let chars = Array(expression)
        let unaryMinus = start > 0 && chars[start - 1] == "−"
            && (start == 1 || "+−×÷(".contains(chars[start - 2]))
        if unaryMinus {
            expression = String(chars[..<(start - 1)] + chars[start...])
        } else {
            expression = String(chars[..<start]) + "−" + String(chars[start...])
        }
    }

    public func refreshRecent() {
        recent = (try? store.recent(limit: 8)) ?? []
    }

    /// Canonical results use ASCII "-"; expressions use "−".
    private static func asExpression(_ result: String) -> String {
        result.replacingOccurrences(of: "-", with: "−")
    }
}
