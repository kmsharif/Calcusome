import CalcCore
import SwiftUI

struct KeypadView: View {
    @Environment(CalculatorModel.self) private var model
    @Environment(\.theme) private var theme
    var spacing: CGFloat = 10

    private enum Style { case digit, function, op, equals }

    private struct Spec: Identifiable {
        let key: Key
        let title: String
        let label: String
        let style: Style
        var span = 1
        var id: String { title }
    }

    private static func digit(_ d: Int) -> Spec { Spec(key: .digit(d), title: "\(d)", label: "\(d)", style: .digit) }

    private let memoryRow: [Spec] = [
        Spec(key: .memoryClear, title: "MC", label: "memory clear", style: .function),
        Spec(key: .memoryRecall, title: "MR", label: "memory recall", style: .function),
        Spec(key: .memorySubtract, title: "M−", label: "memory minus", style: .function),
        Spec(key: .memoryAdd, title: "M+", label: "memory plus", style: .function),
    ]

    private let utilityRow: [Spec] = [
        Spec(key: .openParen, title: "(", label: "open parenthesis", style: .function),
        Spec(key: .closeParen, title: ")", label: "close parenthesis", style: .function),
        Spec(key: .backspace, title: "⌫", label: "delete", style: .function),
    ]

    private let rows: [[Spec]] = [
        [Spec(key: .clear, title: "C", label: "clear", style: .function),
         Spec(key: .negate, title: "±", label: "negate", style: .function),
         Spec(key: .percent, title: "%", label: "percent", style: .function),
         Spec(key: .divide, title: "÷", label: "divide", style: .op)],
        [digit(7), digit(8), digit(9), Spec(key: .multiply, title: "×", label: "multiply", style: .op)],
        [digit(4), digit(5), digit(6), Spec(key: .subtract, title: "−", label: "minus", style: .op)],
        [digit(1), digit(2), digit(3), Spec(key: .add, title: "+", label: "plus", style: .op)],
        [Spec(key: .digit(0), title: "0", label: "0", style: .digit, span: 2),
         Spec(key: .decimal, title: ".", label: "decimal point", style: .digit),
         Spec(key: .equals, title: "=", label: "equals", style: .equals)],
    ]

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            GridRow {
                ForEach(memoryRow) { spec in button(spec).frame(maxHeight: 44) }
            }
            GridRow {
                ForEach(utilityRow) { spec in button(spec).frame(maxHeight: 44) }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(rows[r]) { spec in
                        button(spec).gridCellColumns(spec.span)
                    }
                }
            }
        }
        .frame(maxHeight: 520)
    }

    private func button(_ spec: Spec) -> some View {
        Button { model.press(spec.key) } label: {
            Text(spec.title)
                .font(theme.keyFont)
                .minimumScaleFactor(0.5)  // keys shrink with the window
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(theme.keyText)
                .background(color(spec.style), in: .rect(cornerRadius: theme.keyCornerRadius))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.label)
    }

    private func color(_ style: Style) -> Color {
        switch style {
        case .digit: theme.keyColor
        case .function: theme.functionKeyColor
        case .op: theme.operatorColor
        case .equals: theme.equalsColor
        }
    }
}
