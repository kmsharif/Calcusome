import CalcCore
import SwiftUI

struct CalculatorView: View {
    @Environment(CalculatorModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @AppStorage(Pref.resultFormat) private var format = ResultFormat.decimal
    @AppStorage(Pref.grouping) private var grouping = true
    @AppStorage(Pref.showKeypad) private var showKeypad = true
    @AppStorage(Pref.showRecent) private var showRecent = true
    @AppStorage(Pref.copyOnEquals) private var copyOnEquals = false
    @State private var compact = false  // short window: tighter spacing, no recent chips

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Spacer(minLength: 0)
            display
            if showRecent && !compact { RecentChipsView() }
            if showKeypad {
                KeypadView(spacing: compact ? 6 : 10)
                    .simultaneousGesture(TapGesture().onEnded { focused = true })  // take typing back from the search field
            }
        }
        .padding(compact ? 10 : 16)
        .onGeometryChange(for: Bool.self) { $0.size.height < 480 } action: { compact = $0 }
        .background(theme.background)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .defaultFocus($focused, true)
        .background {
            // A window-level shortcut, so Return evaluates even when keyboard navigation
            // has focused a chip, history row, or key (onKeyPress only sees our own focus).
            Button("Equals") { model.press(.equals) }
                .keyboardShortcut(.defaultAction)
                .hidden()
        }
        .onKeyPress(.delete) { model.press(.backspace); return .handled }
        .onKeyPress(.escape) { model.press(.clear); return .handled }
        .onKeyPress { press in
            guard press.modifiers.isDisjoint(with: [.command, .control]),
                  let c = press.characters.first, let key = Key(typed: c, locale: locale) else { return .ignored }
            model.press(key)
            return .handled
        }
        #if os(macOS)
        .pasteDestination(for: String.self) { strings in
            model.paste(strings.first ?? "")
        }
        #endif
        .sensoryFeedback(.impact, trigger: model.result)
        .onChange(of: model.result) { if copyOnEquals, model.result != nil { Clipboard.copy(primaryLine) } }
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
                .lineLimit(formatted != nil && format == .binary ? 2 : 1)
                .minimumScaleFactor(0.18)  // a grouped 34-digit result still fits the minimum window
                .truncationMode(model.result == nil ? .head : .tail)  // keep the digits just typed visible
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .snappy, value: primaryLine)
                .accessibilityAddTraits(.updatesFrequently)
            HStack(spacing: 6) {
                if model.memory != nil {
                    Text("M")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityLabel("Memory in use")
                }
                formatMenu
            }
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
        if let preview = model.preview { return "= " + InputNormalizer.display(result: preview, locale: locale, grouping: grouping) }
        return model.result == nil ? " " : expressionText
    }

    private var primaryLine: String {
        if let formatted { return formatted }
        if let result = model.result { return InputNormalizer.display(result: result, locale: locale, grouping: grouping) }
        return expressionText.isEmpty ? "0" : expressionText
    }

    /// The result in the chosen non-decimal format, when it can be shown that way.
    private var formatted: String? { model.result.flatMap(format.render) }

    private var formatMenu: some View {
        let applies = format == .decimal || formatted != nil
        return Menu {
            Picker("Result format", selection: $format) {
                ForEach(ResultFormat.allCases, id: \.self) { Text($0.name).tag($0) }
            }
        } label: {
            Text(format.badge)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(applies ? theme.resultColor : theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.functionKeyColor.opacity(applies ? 1 : 0.5), in: .capsule)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Result format, \(format.name)")
    }

    static func message(for error: CalcError) -> String {
        switch error {
        case .syntax: "Incomplete"
        case .divideByZero: "Can't divide by 0"
        case .overflow: "Too large"
        }
    }
}
