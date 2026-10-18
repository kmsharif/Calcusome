import CalcCore
import SwiftUI

/// ⌘, on Mac; the gear button's sheet on iPad.
struct SettingsView: View {
    let store: HistoryStore
    @AppStorage(Pref.theme) private var themeID = Theme.graphite.id
    @AppStorage(Pref.size) private var size = DisplaySize.medium
    @AppStorage(Pref.resultFormat) private var format = ResultFormat.decimal
    @AppStorage(Pref.grouping) private var grouping = true
    @AppStorage(Pref.showKeypad) private var showKeypad = true
    @AppStorage(Pref.showRecent) private var showRecent = true
    @AppStorage(Pref.copyOnEquals) private var copyOnEquals = false
    @AppStorage(Pref.autoClearDays) private var autoClearDays = 0
    #if os(macOS)
    @AppStorage(Pref.menuBar) private var menuBar = true
    @AppStorage(Pref.hotkey) private var hotkey = true
    #endif
    @State private var csv: CSVFile?
    @State private var clearing = false

    var body: some View {
        Form {
            Section("Appearance") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 12)], spacing: 12) {
                    ForEach(Theme.all) { themeCell($0) }
                }
                .padding(.vertical, 4)
                Picker("Size", selection: $size) {
                    ForEach(DisplaySize.allCases, id: \.self) { Text($0.name).tag($0) }
                }
            }

            Section("Results") {
                Picker("Format", selection: $format) {
                    ForEach(ResultFormat.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Toggle("Grouping separators", isOn: $grouping)
            }

            Section("Keypad & Behavior") {
                Toggle("Show keypad", isOn: $showKeypad)
                Toggle("Show recent results", isOn: $showRecent)
                Toggle("Copy result on =", isOn: $copyOnEquals)
            }

            Section("History") {
                Picker("Auto clear", selection: $autoClearDays) {
                    Text("Never").tag(0)
                    Text("After 1 day").tag(1)
                    Text("After 7 days").tag(7)
                    Text("After 30 days").tag(30)
                }
                Button("Export…") { csv = try? CSVFile(store: store) }
                Button("Clear History…", role: .destructive) { clearing = true }
            }

            #if os(macOS)
            Section("Mac") {
                Toggle("Menu bar calculator", isOn: $menuBar)
                Toggle("Global shortcut ⌥⌘=", isOn: $hotkey)
            }
            #endif
        }
        .formStyle(.grouped)
        .historyTools(store: store, csv: $csv, clearing: $clearing)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(width: 460)
        .frame(minHeight: 560)
        #endif
    }

    private func themeCell(_ theme: Theme) -> some View {
        let selected = theme.id == themeID
        return Button { themeID = theme.id } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.background)
                    .frame(height: 52)
                    .overlay {
                        HStack(spacing: 5) {
                            Circle().fill(theme.keyColor)
                            Circle().fill(theme.operatorColor)
                            Circle().fill(theme.equalsColor)
                        }
                        .frame(height: 16)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: selected ? 3 : 1)
                    }
                Text(theme.name).font(.caption)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Theme, \(theme.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
