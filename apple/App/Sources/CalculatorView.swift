import CalcCore
import SwiftUI

struct CalculatorView: View {
    @Environment(CalculatorModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            display
            RecentChipsView()
            KeypadView()
        }
        .padding()
        .background(theme.background)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .defaultFocus($focused, true)
        .onKeyPress(.return) { model.press(.equals); return .handled }
        .onKeyPress(.delete) { model.press(.backspace); return .handled }
        .onKeyPress(.escape) { model.press(.clear); return .handled }
        .onKeyPress { press in
            guard press.modifiers.isDisjoint(with: [.command, .control]),
                  let c = press.characters.first, let key = Key(typed: c) else { return .ignored }
            model.press(key)
            return .handled
        }
        #if os(macOS)
        .pasteDestination(for: String.self) { strings in
            model.paste(strings.first ?? "")
        }
        #endif
        .sensoryFeedback(.impact, trigger: model.result)
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(secondaryLine)
                .font(.title2.monospacedDigit())
                .foregroundStyle(model.error == nil ? theme.secondaryText : theme.operatorColor)
                .lineLimit(1)
                .truncationMode(.head)
            Text(primaryLine)
                .font(theme.displayFont.monospacedDigit())
                .foregroundStyle(theme.resultColor)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .snappy, value: primaryLine)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(.rect)
        .contextMenu {
            // ponytail: iPad ⌘V needs pasteDestination (iOS 27+); long-press paste covers iPadOS 18–26.
            PasteButton(payloadType: String.self) { strings in model.paste(strings.first ?? "") }
        }
    }

    private var expressionText: String {
        InputNormalizer.display(expression: model.expression, locale: locale)
    }

    private var secondaryLine: String {
        if let error = model.error { return Self.message(for: error) }
        return model.result == nil ? " " : expressionText
    }

    private var primaryLine: String {
        if let result = model.result { return InputNormalizer.display(result: result, locale: locale) }
        return expressionText.isEmpty ? "0" : expressionText
    }

    static func message(for error: CalcError) -> String {
        switch error {
        case .syntax: "Incomplete"
        case .divideByZero: "Can't divide by 0"
        case .overflow: "Too large"
        }
    }
}
