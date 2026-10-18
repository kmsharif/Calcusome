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
        case .equals: evaluate()
        case .clear: expression = ""; result = nil; lastSaved = nil
        case .backspace: startEditing(); if !expression.isEmpty { expression.removeLast() }
        case .negate: startEditing(); negateLastNumber()
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
        expression += Self.asExpression(entry.result)
        error = nil
    }

    private func evaluate() {
        do {
            let value = DecimalRounding.canonical(try Engine.evaluate(expression))
            result = value
            guard expression != lastSaved else { return }
            _ = try? store.add(expression: expression, result: value)
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

    private func negateLastNumber() {
        let chars = Array(expression)
        var start = chars.count
        while start > 0, chars[start - 1].isNumber || chars[start - 1] == "." { start -= 1 }
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
