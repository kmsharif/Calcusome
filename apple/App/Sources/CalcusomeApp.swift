import CalcCore
import SwiftData
import SwiftUI

@main
struct CalcusomeApp: App {
    private let store: HistoryStore
    private let container: ModelContainer
    #if os(macOS)
    @AppStorage(Pref.menuBar) private var showMenuBar = true
    @AppStorage(Pref.hotkey) private var hotkeyEnabled = true
    @State private var hotkey: GlobalHotkey?
    #endif

    init() {
        do {
            container = try ModelContainer(for: HistoryEntry.self)
        } catch {
            fatalError("History store failed to open: \(error)")
        }
        store = HistoryStore(container: container, deviceID: DeviceID.current())
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
        .modelContainer(container)
        .defaultSize(width: 920, height: 760)
        #if os(macOS)
        .onChange(of: hotkeyEnabled, initial: true) {
            hotkey = hotkeyEnabled ? GlobalHotkey {
                NSApp.activate()
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            } : nil  // releasing it unregisters the shortcut
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(store: store)
        }

        MenuBarExtra("Calcusome", systemImage: "plus.forwardslash.minus", isInserted: $showMenuBar) {
            MenuBarCalculator(store: store)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

/// One window: its own calculator input, the shared history.
struct RootView: View {
    let store: HistoryStore
    @State private var model: CalculatorModel
    @AppStorage("showHistory") private var showHistory = true
    @State private var showSettings = false
    @AppStorage(Pref.autoClearDays) private var autoClearDays = 0
    @AppStorage(Pref.showKeypad) private var showKeypad = true
    @SceneStorage("pinned") private var pinned = false
    @Environment(\.scenePhase) private var scenePhase

    init(store: HistoryStore) {
        self.store = store
        _model = State(initialValue: CalculatorModel(store: store))
    }

    // Plain side-by-side split: NavigationSplitView turns the sidebar into an overlay in narrow windows.
    var body: some View {
        HStack(spacing: 0) {
            if showHistory {
                NavigationStack {
                    HistoryView(store: store)
                        .toolbar { ToolbarItem(placement: .navigation) { historyToggle } }
                }
                .frame(width: 300)
                .transition(.move(edge: .leading))
                Divider()
            }
            NavigationStack {
                CalculatorView()
                    .toolbar {
                        if !showHistory { ToolbarItem(placement: .navigation) { historyToggle } }
                        #if os(iOS)
                        ToolbarItem { Button("Settings", systemImage: "gearshape") { showSettings = true } }
                        #else
                        ToolbarItem {
                            Button(pinned ? "Unpin Window" : "Keep on Top", systemImage: pinned ? "pin.fill" : "pin") {
                                pinned.toggle()
                            }
                            .help(pinned ? "Unpin Window" : "Keep on Top")
                        }
                        #endif
                    }
            }
        }
        .animation(.snappy, value: showHistory)
        .environment(model)
        .themed()
        #if os(macOS)
        .frame(minWidth: 680, minHeight: showKeypad ? 640 : 320)
        .background(FloatingWindow(floating: pinned))
        #else
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(store: store)
                    .toolbar { Button("Done") { showSettings = false } }
            }
        }
        #endif
        .onChange(of: scenePhase, initial: true) { if scenePhase == .active { autoClear() } }
        .onChange(of: autoClearDays) { autoClear() }
    }

    private var historyToggle: some View {
        Button(showHistory ? "Hide History" : "Show History", systemImage: "sidebar.left") { showHistory.toggle() }
            .keyboardShortcut("s", modifiers: [.command, .control])
    }

    private func autoClear() {
        guard autoClearDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -autoClearDays, to: .now) else { return }
        try? store.deleteUnpinned(before: cutoff)
    }
}

#if os(macOS)
/// Floats the hosting window above every other app's windows while `floating` is on.
struct FloatingWindow: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view joins its window after the first update, so set the level on the next turn.
        DispatchQueue.main.async { view.window?.level = floating ? .floating : .normal }
    }
}

struct MenuBarCalculator: View {
    @State private var model: CalculatorModel
    @AppStorage(Pref.showKeypad) private var showKeypad = true

    init(store: HistoryStore) {
        _model = State(initialValue: CalculatorModel(store: store))
    }

    var body: some View {
        CalculatorView()
            .environment(model)
            .themed(display: 44)
            .frame(width: 300, height: showKeypad ? 480 : 220)
    }
}
#endif
