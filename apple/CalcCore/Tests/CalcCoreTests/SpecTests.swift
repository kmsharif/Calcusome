import Foundation
import Testing
@testable import CalcCore

struct SpecCase: Decodable, Sendable, CustomTestStringConvertible {
    let id: String
    let input: String
    let locale: String?
    let expression: String?
    let result: String?
    let error: String?
    var testDescription: String { id }
}

private struct SpecFile: Decodable { let cases: [SpecCase] }

// SwiftPM can't bundle files outside the package, so read the shared spec by path.
func loadSpec(_ name: String) -> [SpecCase] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("spec/\(name)")
    let data = try! Data(contentsOf: url)
    return try! JSONDecoder().decode(SpecFile.self, from: data).cases
}

let specCases = loadSpec("math-cases.json")
/// Differential cases from spec/generate_cases.py (Python decimal, 34 digits, half-even).
let generatedCases = loadSpec("math-generated.json")

@Test(arguments: specCases)
func spec(_ c: SpecCase) throws {
    var expression = c.input
    if let locale = c.locale {
        expression = InputNormalizer.normalize(c.input, locale: Locale(identifier: locale))
        #expect(expression == c.expression)
    }
    if let result = c.result {
        #expect(try Engine.evaluate(expression) == result)
    } else {
        #expect(throws: CalcError(rawValue: c.error!)!) { try Engine.evaluate(expression) }
    }
}

@Test func generated() throws {
    var failures: [String] = []
    for c in generatedCases {
        let got = (try? Engine.evaluate(c.input)) ?? "error"
        if got != c.result { failures.append("\(c.id): \(c.input) → \(got), want \(c.result!)") }
    }
    #expect(failures.isEmpty, "\(failures.count)/\(generatedCases.count) wrong, first: \(failures.prefix(3))")
}

@Test func displayFormatsForLocale() {
    let de = Locale(identifier: "de_DE"), en = Locale(identifier: "en_US")
    #expect(InputNormalizer.display(result: "1234.5", locale: de) == "1.234,5")
    #expect(InputNormalizer.display(result: "1234.5", locale: en) == "1,234.5")
    #expect(InputNormalizer.display(result: "0.3333333333333333333333333333333333", locale: en)
            == "0.3333333333333333333333333333333333")
    #expect(InputNormalizer.display(expression: "1.5×2", locale: de) == "1,5×2")
}
