import CalcCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    let store: HistoryStore
    @Environment(CalculatorModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var entries: [HistoryEntry] = []
    @State private var query = ""
    @State private var labelling: HistoryEntry?
    @State private var labelText = ""
    @State private var csv: CSVFile?
    @State private var clearing = false
    @State private var hovered: HistoryEntry.ID?
    @State private var hoveringList = false  // scroll bar only while the pointer is over the list
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.entries) { row($0) }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .scrollIndicators(hoveringList ? .visible : .never)  // .hidden still shows under "Always show scroll bars"
        .onHover { hoveringList = $0 }
        .navigationTitle("History")
        .searchable(text: $query, prompt: "Search labels and expressions")
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No calculations yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .toolbar {
            Menu("History Tools", systemImage: "ellipsis.circle") {
                Button("Export…", systemImage: "square.and.arrow.up") { csv = try? CSVFile(store: store) }
                Button("Clear History…", systemImage: "trash", role: .destructive) { clearing = true }
            }
        }
        .historyTools(store: store, csv: $csv, clearing: $clearing)
        .task(id: store.revision) { reload() }
        .onChange(of: query) { reload() }
        .alert("Label", isPresented: Binding(get: { labelling != nil }, set: { if !$0 { labelling = nil } }),
               presenting: labelling) { entry in
            TextField("e.g. Rent split", text: $labelText)
            Button("Save") { mutate { try store.setLabel(entry, labelText) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { model.reuse(entry) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let label = entry.label {
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(InputNormalizer.display(result: entry.result, locale: locale))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            Button { model.reuse(entry, expression: true) } label: {
                Text(InputNormalizer.display(expression: entry.expression, locale: locale))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered == entry.id ? Color.primary.opacity(0.08) : .clear)
                .padding(.horizontal, 8)
        )
        .onHover { inside in
            if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
        }
        .contextMenu { actions(entry) }
        .swipeActions(edge: .trailing) { actions(entry) }
    }

    @ViewBuilder private func actions(_ entry: HistoryEntry) -> some View {
        Button(role: .destructive) { mutate { try store.delete(entry) } } label: { Label("Delete", systemImage: "trash") }
        Button { mutate { try store.setPinned(entry, !entry.pinned) } } label: {
            Label(entry.pinned ? "Remove Bookmark" : "Bookmark", systemImage: entry.pinned ? "bookmark.slash" : "bookmark")
        }
        Button { Clipboard.copy(InputNormalizer.display(result: entry.result, locale: locale)) } label: {
            Label("Copy Result", systemImage: "doc.on.doc")
        }
        Button { labelText = entry.label ?? ""; labelling = entry } label: { Label("Label…", systemImage: "tag") }
    }

    private func mutate(_ change: () throws -> Void) {
        try? change()  // the store's revision bump reloads every window
    }

    private func reload() {
        entries = (try? query.isEmpty ? store.all() : store.search(query, locale: locale)) ?? []
    }

    private var sections: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var result: [(title: String, entries: [HistoryEntry])] = []
        let pinned = entries.filter(\.pinned)
        if !pinned.isEmpty { result.append(("Bookmarked", pinned)) }
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

/// History as a `.csv` file for `fileExporter`.
struct CSVFile: Transferable {
    let text: String

    @MainActor init(store: HistoryStore) throws { text = try store.exportCSV() }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
    }
}

extension View {
    /// Export and Clear History presentation, shared by the history toolbar and Settings.
    func historyTools(store: HistoryStore, csv: Binding<CSVFile?>, clearing: Binding<Bool>) -> some View {
        modifier(HistoryTools(store: store, csv: csv, clearing: clearing))
    }
}

private struct HistoryTools: ViewModifier {
    let store: HistoryStore
    @Binding var csv: CSVFile?
    @Binding var clearing: Bool
    @Environment(Account.self) private var account

    func body(content: Content) -> some View {
        content.fileExporter(isPresented: Binding(get: { csv != nil }, set: { if !$0 { csv = nil } }),
                     item: csv, contentTypes: [.commaSeparatedText],
                     defaultFilename: "Calcusome History") { _ in }
        .confirmationDialog("Clear history?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { try? store.deleteUnpinned(before: .now) }
        } message: {
            Text(account.state == .signedOut
                 ? "Bookmarked calculations are kept."
                 : "Bookmarked calculations are kept. This clears history on all your signed-in devices.")
        }
    }
}
