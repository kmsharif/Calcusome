import CalcCore
import SwiftData
import SwiftUI

@main
struct CalcusomeApp: App {
    private let store: HistoryStore
    private let account: Account
    private let container: ModelContainer
    #if os(macOS)
    @AppStorage(Pref.menuBar) private var showMenuBar = true
    @AppStorage(Pref.hotkey) private var hotkeyEnabled = true
    @State private var hotkey: GlobalHotkey?
    private let updater = Updater()
    #endif

    init() {
        do {
            container = try ModelContainer(for: HistoryEntry.self)
        } catch {
            fatalError("History store failed to open: \(error)")
        }
        store = HistoryStore(container: container, deviceID: DeviceID.current())
        account = Account(store: store)
        #if os(macOS)
        updater.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environment(account)
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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(manual: true) } }
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(store: store)
                .environment(account)
        }

        MenuBarExtra("Calcusome", systemImage: "plus.forwardslash.minus", isInserted: $showMenuBar) {
            MenuBarCalculator(store: store)
                .environment(account)
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
    @AppStorage("historyWidth") private var historyWidth = 300.0
    @State private var dragStartWidth: Double?
    @State private var rootWidth = Double.infinity
    @State private var showSettings = false
    @AppStorage(Pref.autoClearDays) private var autoClearDays = 0
    @AppStorage(Pref.showKeypad) private var showKeypad = true
    @SceneStorage("pinned") private var pinned = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Account.self) private var account

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
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading))
                Divider()
                    .overlay {
                        Color.clear
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            #if os(macOS)
                            .pointerStyle(.columnResize)
                            #endif
                            .gesture(resizeDrag)
                    }
                    .zIndex(1)  // keep the grab area above the calculator
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
        .onGeometryChange(for: Double.self) { $0.size.width } action: { rootWidth = $0 }
        #if os(macOS)
        .frame(minWidth: 230, minHeight: showKeypad ? 380 : 200)
        .onGeometryChange(for: Bool.self) { $0.size.width < Self.sidebarMinWidth + Self.calculatorMinWidth } action: { tooNarrow in
            if tooNarrow { showHistory = false }  // dragging the window narrow folds the sidebar away
        }
        .toolbar(removing: .title)  // like Calculator.app; keeps the narrow toolbar from overflowing
        .background(FloatingWindow(floating: pinned))
        #else
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(store: store)
                    .toolbar { Button("Done") { showSettings = false } }
            }
        }
        #endif
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            autoClear()
            account.sync?.scheduleSync(after: .zero)
        }
        .onChange(of: autoClearDays) { autoClear() }
    }

    private var historyToggle: some View {
        Button(showHistory ? "Hide History" : "Show History", systemImage: "sidebar.left") {
            showHistory.toggle()
            #if os(macOS)
            // Make room for the sidebar instead of letting the width check fold it away again.
            if showHistory, let window = NSApp.keyWindow, window.frame.width < historyWidth + Self.calculatorMinWidth {
                var frame = window.frame
                frame.size.width = historyWidth + Self.calculatorMinWidth + 60
                window.setFrame(frame, display: true, animate: true)
            }
            #endif
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
    }

    /// Narrowest the sidebar gets; dragging the divider `collapseOvershoot` past it hides the sidebar.
    private static let sidebarMinWidth = 220.0
    private static let collapseOvershoot = 60.0
    /// Divider + the calculator's minimum width.
    private static let calculatorMinWidth = 231.0

    /// The saved width, squeezed so the calculator keeps its minimum width.
    private var sidebarWidth: Double {
        max(Self.sidebarMinWidth, min(historyWidth, rootWidth - Self.calculatorMinWidth))
    }

    private var resizeDrag: some Gesture {
        // Global space: the divider moves with the drag, so local translations would jitter.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in
                let start = dragStartWidth ?? sidebarWidth
                dragStartWidth = start
                let proposed = start + drag.translation.width
                if proposed < Self.sidebarMinWidth - Self.collapseOvershoot {
                    dragStartWidth = nil
                    showHistory = false
                } else {
                    historyWidth = max(Self.sidebarMinWidth, min(proposed, rootWidth - Self.calculatorMinWidth))
                }
            }
            .onEnded { _ in dragStartWidth = nil }
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
