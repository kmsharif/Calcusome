import CalcCore
import SwiftData
import SwiftUI

@main
struct CalcusomeApp: App {
    @State private var model: CalculatorModel
    private let store: HistoryStore
    private let container: ModelContainer
    #if os(macOS)
    private let hotkey = GlobalHotkey {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
    #endif

    init() {
        do {
            container = try ModelContainer(for: HistoryEntry.self)
        } catch {
            fatalError("History store failed to open: \(error)")
        }
        store = HistoryStore(container: container, deviceID: DeviceID.current())
        _model = State(initialValue: CalculatorModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environment(model)
                #if os(macOS)
                .frame(minWidth: 680, minHeight: 640)
                #endif
        }
        .modelContainer(container)
        .defaultSize(width: 920, height: 760)

        #if os(macOS)
        MenuBarExtra("Calcusome", systemImage: "plus.forwardslash.minus") {
            CalculatorView()
                .environment(model)
                .frame(width: 300, height: 480)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

struct RootView: View {
    let store: HistoryStore
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            HistoryView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            CalculatorView()
        }
    }
}
