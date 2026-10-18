import CalcCore
import SwiftUI

/// Recent results as tappable chips; a tap drops the value into the current expression.
struct RecentChipsView: View {
    @Environment(CalculatorModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.recent) { entry in
                    Button { model.reuse(entry) } label: {
                        Text(InputNormalizer.display(result: entry.result, locale: locale))
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(theme.resultColor)
                            .background(theme.functionKeyColor, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(entry.result)")
                }
            }
        }
        .frame(height: model.recent.isEmpty ? 0 : 34)
    }
}
