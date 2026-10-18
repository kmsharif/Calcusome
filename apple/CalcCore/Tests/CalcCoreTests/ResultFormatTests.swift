import Testing
@testable import CalcCore

struct ResultFormatTests {
    func fraction(_ expression: String) throws -> String? {
        ResultFormat.fraction.render(try Engine.evaluate(expression))
    }

    @Test func fractions() throws {
        #expect(try fraction("1÷3") == "1/3")
        #expect(try fraction("2÷3") == "2/3")  // 0.666…67 still finds 2/3
        #expect(try fraction("4÷3") == "1 1/3")
        #expect(try fraction("1÷7") == "1/7")
        #expect(try fraction("−0.75") == "-3/4")
        #expect(try fraction("1÷997") == "1/997")
        #expect(try fraction("22÷7") == "3 1/7")
    }

    @Test func fractionUnavailable() {
        #expect(ResultFormat.fraction.render("5") == nil)  // already exact
        #expect(ResultFormat.fraction.render("0.1234567") == nil)  // denominator over the cap
        #expect(ResultFormat.fraction.render("0." + String(repeating: "0", count: 40) + "1") == nil)
    }

    @Test func bases() {
        #expect(ResultFormat.hex.render("255") == "FF")
        #expect(ResultFormat.octal.render("255") == "377")
        #expect(ResultFormat.binary.render("255") == "1111 1111")
        #expect(ResultFormat.binary.render("5") == "0101")
        #expect(ResultFormat.hex.render("-10") == "-A")
        #expect(ResultFormat.hex.render("0") == "0")
        #expect(ResultFormat.hex.render("0.5") == nil)
        #expect(ResultFormat.hex.render(String(repeating: "9", count: 34)) == "1ED09BEAD87C0378D8E63FFFFFFFF")
    }

    @Test func decimalIsCallersText() {
        #expect(ResultFormat.decimal.render("1.5") == nil)
    }
}
