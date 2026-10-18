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
let specCases: [SpecCase] = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("spec/math-cases.json")
    let data = try! Data(contentsOf: url)
    return try! JSONDecoder().decode(SpecFile.self, from: data).cases
}()

@Test(arguments: specCases)
func spec(_ c: SpecCase) throws {
    let expression = c.input
    if let result = c.result {
        #expect(DecimalRounding.canonical(try Engine.evaluate(expression)) == result)
    } else {
        #expect(throws: CalcError(rawValue: c.error!)!) { try Engine.evaluate(expression) }
    }
}
