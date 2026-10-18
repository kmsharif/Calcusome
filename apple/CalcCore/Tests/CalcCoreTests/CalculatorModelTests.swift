import Foundation
import Testing
@testable import CalcCore

@MainActor struct CalculatorModelTests {
    let store: HistoryStore
    let model: CalculatorModel

    init() throws {
        store = try HistoryStore.inMemory()
        model = CalculatorModel(store: store, locale: Locale(identifier: "en_US"))
    }

    func press(_ keys: Key...) { keys.forEach(model.press) }

    @Test func typingBuildsCanonical() {
        press(.digit(1), .digit(2), .multiply, .digit(3))
        #expect(model.expression == "12×3")
    }

    @Test func equalsSavesOnce() throws {
        press(.digit(2), .add, .digit(2), .equals, .equals)
        #expect(model.result == "4")
        #expect(try store.all().count == 1)
    }

    @Test func incompleteDoesNothing() throws {
        press(.digit(5), .add, .equals)
        #expect(model.error == .syntax)
        #expect(model.expression == "5+")
        #expect(try store.all().isEmpty)
    }

    @Test func divideByZeroNotSaved() throws {
        press(.digit(1), .divide, .digit(0), .equals)
        #expect(model.error == .divideByZero)
        #expect(try store.all().isEmpty)
    }

    @Test func errorClearsOnNextKey() {
        press(.digit(5), .add, .equals, .digit(1))
        #expect(model.error == nil)
        #expect(model.expression == "5+1")
    }

    @Test func digitAfterResultStartsFresh() {
        press(.digit(2), .add, .digit(2), .equals, .digit(5))
        #expect(model.expression == "5")
        #expect(model.result == nil)
    }

    @Test func operatorAfterResultContinues() {
        press(.digit(2), .add, .digit(2), .equals, .add)
        #expect(model.expression == "4+")
    }

    @Test func negativeResultContinuesWithCanonicalMinus() {
        press(.digit(1), .subtract, .digit(4), .equals, .multiply)
        #expect(model.expression == "−3×")
    }

    @Test func negateTogglesLastNumber() {
        press(.digit(5), .negate)
        #expect(model.expression == "−5")
        press(.negate)
        #expect(model.expression == "5")
        press(.add, .digit(3), .negate)
        #expect(model.expression == "5+−3")
    }

    @Test func percentParensAndDecimal() {
        press(.openParen, .digit(1), .decimal, .digit(5), .closeParen, .percent)
        #expect(model.expression == "(1.5)%")
    }

    @Test func backspaceAndClear() {
        press(.digit(1), .digit(2), .backspace)
        #expect(model.expression == "1")
        press(.add, .equals, .clear)
        #expect(model.expression == "")
        #expect(model.result == nil)
        #expect(model.error == nil)
    }

    @Test func pasteNormalizes() throws {
        let de = CalculatorModel(store: store, locale: Locale(identifier: "de_DE"))
        de.paste("1.234,5+1")
        #expect(de.expression == "1234.5+1")
    }

    @Test func reuseAppendsResult() throws {
        press(.digit(2), .add, .digit(2), .equals, .add)
        model.reuse(try #require(model.recent.first))
        #expect(model.expression == "4+4")
    }

    @Test func reuseAfterResultReplaces() throws {
        press(.digit(2), .add, .digit(2), .equals)
        model.reuse(try #require(model.recent.first))
        #expect(model.expression == "4")
    }

    @Test func recentRefreshes() {
        press(.digit(2), .add, .digit(2), .equals)
        #expect(model.recent.first?.result == "4")
    }
}

@Test func typedCharactersMapToKeys() {
    #expect(Key(typed: "7") == .digit(7))
    #expect(Key(typed: ".") == .decimal)
    #expect(Key(typed: "+") == .add)
    #expect(Key(typed: "-") == .subtract)
    #expect(Key(typed: "*") == .multiply)
    #expect(Key(typed: "x") == .multiply)
    #expect(Key(typed: "/") == .divide)
    #expect(Key(typed: "%") == .percent)
    #expect(Key(typed: "(") == .openParen)
    #expect(Key(typed: ")") == .closeParen)
    #expect(Key(typed: "=") == .equals)
    #expect(Key(typed: "\r") == .equals)
    #expect(Key(typed: "a") == nil)
}

@Test func typedCommaFollowsLocale() {
    #expect(Key(typed: ",", locale: Locale(identifier: "en_US")) == nil)
    #expect(Key(typed: ",", locale: Locale(identifier: "de_DE")) == .decimal)
    #expect(Key(typed: ".", locale: Locale(identifier: "de_DE")) == .decimal)
}

extension CalculatorModelTests {
    @Test func reuseAfterNumberMultiplies() throws {
        press(.digit(8), .equals, .digit(1), .digit(2))
        model.reuse(try #require(model.recent.first))
        #expect(model.expression == "12×8")
    }

    @Test func reuseAfterParenMultiplies() throws {
        press(.digit(8), .equals, .openParen, .digit(2), .closeParen)
        model.reuse(try #require(model.recent.first))
        #expect(model.expression == "(2)×8")
    }

    @Test func negateAfterResultNegatesResult() {
        press(.digit(5), .add, .digit(3), .equals, .negate)
        #expect(model.expression == "−8")
        #expect(model.result == nil)
    }

    @Test func leadingDecimalPointEvaluates() {
        press(.decimal, .digit(5), .multiply, .digit(2), .equals)
        #expect(model.result == "1")
    }

    @Test func secondDecimalPointIgnored() {
        press(.digit(1), .decimal, .digit(2), .decimal, .digit(3))
        #expect(model.expression == "1.23")
        press(.add, .digit(4), .decimal)
        #expect(model.expression == "1.23+4.")
    }
}

@Test func typedNativeDigitsMapToKeys() {
    #expect(Key(typed: "৫") == .digit(5))
    #expect(Key(typed: "٧") == .digit(7))
    #expect(Key(typed: "۳") == .digit(3))
}

@Test func numpadEnterIsEquals() {
    #expect(Key(typed: "\u{3}") == .equals)
}
