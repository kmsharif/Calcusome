import Foundation
import Observation

public enum Key: Hashable, Sendable {
    case digit(Int), decimal, add, subtract, multiply, divide, percent, openParen, closeParen
    case negate, backspace, clear, equals
    case memoryAdd, memorySubtract, memoryRecall, memoryClear

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
    /// Calculator memory (M+, M−, MR, MC), canonical like `result`; nil when empty.
    public private(set) var memory: String?

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var lastSaved: String?

    public init(store: HistoryStore, locale: Locale = .current) {
        self.store = store
        self.locale = locale
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
        case .memoryAdd: addToMemory(negated: false)
        case .memorySubtract: addToMemory(negated: true)
        case .memoryRecall: if let memory { insert(Self.asExpression(memory)) }
        case .memoryClear: memory = nil
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

    /// Chip tap: append a past result (or its expression), or start from it right after "=".
    /// An expression joining existing input is parenthesised so it keeps its meaning.
    public func reuse(_ entry: HistoryEntry, expression useExpression: Bool = false) {
        if useExpression { insert(entry.expression, group: true) } else { insert(Self.asExpression(entry.result)) }
        error = nil
    }

    private func insert(_ text: String, group: Bool = false) {
        startEditing()
        if let last = expression.last, last.isNumber || ".)%".contains(last) { expression.append("×") }
        expression += group && !expression.isEmpty ? "(\(text))" : text
    }

    /// Adds the shown value (the result, or the expression so far) to memory.
    private func addToMemory(negated: Bool) {
        guard let value = result ?? (try? Engine.evaluate(expression)) else { return }
        let operand = "(\(Self.asExpression(value)))"
        do {
            memory = try Engine.evaluate(memory.map { "(\(Self.asExpression($0)))" + (negated ? "−" : "+") + operand }
                                         ?? (negated ? "−" + operand : operand))
        } catch {
            self.error = error
        }
    }

    private func evaluate() {
        do {
            let value = try Engine.evaluate(expression)
            result = value
            guard expression != lastSaved, !isLoneNumber else { return }
            guard (try? store.add(expression: expression, result: value)) != nil else { return }
            lastSaved = expression
        } catch {
            self.error = error
        }
    }

    /// Live result while typing; nil until the expression is complete and does real work.
    public var preview: String? {
        guard result == nil, !isLoneNumber else { return nil }
        return try? Engine.evaluate(expression)
    }

    private var isLoneNumber: Bool {
        expression.drop { $0 == "−" }.allSatisfy { $0.isNumber || $0 == "." }
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

    /// Newest results for the chips; reading `revision` keeps every window in step with the store.
    public var recent: [HistoryEntry] {
        _ = store.revision
        return (try? store.recent(limit: 8)) ?? []
    }

    /// Canonical results use ASCII "-"; expressions use "−".
    private static func asExpression(_ result: String) -> String {
        result.replacingOccurrences(of: "-", with: "−")
    }
}
