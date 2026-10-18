import CalcCore
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    @Environment(CalculatorModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var entries: [HistoryEntry] = []
    @State private var query = ""
    @State private var labelling: HistoryEntry?
    @State private var labelText = ""

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.entries) { row($0) }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $query, prompt: "Search labels and expressions")
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No calculations yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .task(id: model.recent.map(\.id)) { reload() }
        .onChange(of: query) { reload() }
        .alert("Label", isPresented: Binding(get: { labelling != nil }, set: { if !$0 { labelling = nil } }),
               presenting: labelling) { entry in
            TextField("e.g. Rent split", text: $labelText)
            Button("Save") { mutate { try store.setLabel(entry, labelText) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        Button { model.reuse(entry) } label: {
            VStack(alignment: .leading, spacing: 2) {
                if let label = entry.label {
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(InputNormalizer.display(result: entry.result, locale: locale))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(InputNormalizer.display(expression: entry.expression, locale: locale))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu { actions(entry) }
        .swipeActions(edge: .trailing) { actions(entry) }
    }

    @ViewBuilder private func actions(_ entry: HistoryEntry) -> some View {
        Button(role: .destructive) { mutate { try store.delete(entry) } } label: { Label("Delete", systemImage: "trash") }
        Button { mutate { try store.setPinned(entry, !entry.pinned) } } label: {
            Label(entry.pinned ? "Unpin" : "Pin", systemImage: entry.pinned ? "pin.slash" : "pin")
        }
        Button { labelText = entry.label ?? ""; labelling = entry } label: { Label("Label…", systemImage: "tag") }
    }

    private func mutate(_ change: () throws -> Void) {
        try? change()
        model.refreshRecent()
        reload()
    }

    private func reload() {
        entries = (try? query.isEmpty ? store.all() : store.search(query, locale: locale)) ?? []
    }

    private var sections: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var result: [(title: String, entries: [HistoryEntry])] = []
        let pinned = entries.filter(\.pinned)
        if !pinned.isEmpty { result.append(("Pinned", pinned)) }
        for entry in entries where !entry.pinned {
            let title = calendar.isDateInToday(entry.createdAt) ? "Today"
                : calendar.isDateInYesterday(entry.createdAt) ? "Yesterday"
                : entry.createdAt.formatted(date: .abbreviated, time: .omitted)
            if result.last?.title == title { result[result.count - 1].entries.append(entry) }
            else { result.append((title, [entry])) }
        }
        return result
    }
}
