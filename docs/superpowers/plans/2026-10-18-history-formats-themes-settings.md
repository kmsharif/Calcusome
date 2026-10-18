# Calcusome: History Tools, Result Formats, Themes, Advanced Settings

## Context

Screenshot lists five premium-style features. User scoped it to four, **no paywall/gate**, **no unit conversion/live rates**:

1. **History Tools** — bookmark, export, auto clear, and more.
2. **Fractions + other result formats** — fraction (`1/3`, `1 1/3`), hex, binary, octal.
3. **More Themes** — all colors and styles.
4. **Advanced Settings** — hide keypad, multiple windows, sizes, behavior.

Current app (Phase 2 MVP): `CalcCore` Swift package (engine, `HistoryStore` on SwiftData, `CalculatorModel`) + thin SwiftUI app for macOS 15 / iPadOS 18. One theme (`Theme.graphite`), no settings screen, one `CalculatorModel` shared by every window and the menu bar extra.

Global constraints from the MVP plan still hold: decimal-only math, canonical expression/result strings, tombstone deletes, history fields unchanged, every key has a VoiceOver label, Reduce Motion respected. **No change to the engine grammar or `spec/math-cases.json`** — all four features are display/app-layer, so Android parity is unaffected.

## Design decisions (defaults taken, flag if wrong)

- **Bookmark = existing Pin.** Same feature; UI copy renamed "Bookmark" / "Bookmarked" section. No new field.
- **Result format is display-only.** History and chips keep canonical decimal; the chosen format applies to the main result line. Not representable (e.g. `0.5` in hex, fraction denominator > 1,000,000) → show decimal, format badge dimmed.
- **Fractions computed exactly**, no floating point: continued-fraction convergents of the canonical decimal (`N/10^k`) via `Int128`/`UInt128` (available macOS 15 / iOS 18), first convergent `p/q` whose 34-digit rounding (`ExactDecimal(p) / ExactDecimal(q)`) equals the result. So `1÷3` → `1/3`, `2÷3` (`…667`) → `2/3`.
- **Multiple windows = each window gets its own `CalculatorModel`**; history store stays shared and becomes `@Observable` so chips/history update in every window.
- **Settings**: `Settings` scene on Mac (⌘,), gear button → sheet on iPad. Same `SettingsView`. Values in `@AppStorage`.
- **Themes**: 5 named themes; colors are placeholders until the Phase 1 Figma tokens land.

---

## Task 1: Shared observable store, one model per window

**Why first:** multiple windows and every later toggle depend on views reading store changes instead of `model.refreshRecent()` calls.

- `CalcCore/Sources/CalcCore/HistoryStore.swift`: mark `@Observable`; add `public private(set) var revision = 0`, bumped in one private `save()` used by `add` and `touch`.
- `CalcCore/Sources/CalcCore/CalculatorModel.swift`: `recent` becomes computed `{ _ = store.revision; return (try? store.recent(limit: 8)) ?? [] }`; delete `refreshRecent()` and its calls.
- `App/Sources/HistoryView.swift`: `.task(id: store.revision) { reload() }`; `mutate` drops `model.refreshRecent()`.
- `App/Sources/CalcusomeApp.swift`: move `CalculatorModel` creation from the `App` into `RootView` (`@State private var model: CalculatorModel` built from `store`), so each `WindowGroup` window is independent. Menu bar extra builds its own model the same way.
- `App/project.yml`: `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes: YES` (iPad multiple windows; verify key name at build).
- Tests: update `CalculatorModelTests` for removed `refreshRecent`; add one test that two models on one store both see an entry added via the other.

## Task 2: Settings scaffold

- New `App/Sources/SettingsView.swift`: `Form` with sections Appearance, Results, Keypad & Behavior, History, Mac (`#if os(macOS)`). Sections filled by later tasks.
- New `App/Sources/Pref.swift`: `enum Pref` with the `@AppStorage` key strings + defaults (used from several files; avoids typo'd keys).
- `CalcusomeApp.swift`: `#if os(macOS) Settings { SettingsView(store:) } #endif`.
- `RootView`: on iOS, toolbar gear button → `.sheet { NavigationStack { SettingsView(store:) } }`.

## Task 3: History Tools

**Core (`HistoryStore.swift`)**
- `public func deleteUnpinned(before cutoff: Date) throws -> Int` — tombstones live, unpinned entries with `createdAt < cutoff`. Used by both auto clear and "Clear History" (`before: now`).
- `public func exportCSV() throws -> String` — header `date,label,expression,result,bookmarked`; ISO 8601 dates; RFC 4180 quoting (fields with `,` `"` or newline wrapped, `"` doubled); live entries only, newest first.
- Tests in `HistoryStoreTests`: auto clear keeps pinned + recent, tombstones old; deleted never in export; label `Rent, "June"` round-trips quoted.

**App**
- `HistoryView` toolbar `Menu` (ellipsis): **Export…** (`fileExporter` with a 5-line `CSVFile: Transferable` → `.commaSeparatedText`, filename `Calcusome History.csv`), **Clear History…** (`confirmationDialog`: "Bookmarked entries are kept").
- Row actions: rename Pin → **Bookmark** (`bookmark` / `bookmark.slash` symbols), add **Copy Result** (new `App/Sources/Clipboard.swift`: `NSPasteboard`/`UIPasteboard` behind `#if`, ~10 lines). Section title "Pinned" → "Bookmarked".
- Settings → History: **Auto clear** picker (Never / After 1 day / 7 days / 30 days, `Pref.autoClearDays`, default Never), Export…, Clear History….
- Run auto clear in `RootView` `.onChange(of: scenePhase, initial: true)` when `.active` and days > 0.

## Task 4: Result formats (fraction, hex, binary, octal)

**Core** — new `CalcCore/Sources/CalcCore/ResultFormat.swift`:
- `public enum ResultFormat: String, CaseIterable, Sendable { case decimal, fraction, hex, binary, octal }`
- `public static func format(_ canonical: String, as: ResultFormat) -> String?` — nil when not representable.
  - **fraction**: integer → nil (decimal already exact); else convergents as in Design decisions, cap denominator 1,000,000 (`// ponytail:` comment naming the cap); mixed form `1 1/3`, `-1 1/3`; overflow-checked `Int128` math, nil on overflow or exponent too small.
  - **hex/binary/octal**: integer results only, `UInt128` magnitude (|x| < 1e34 < 2^113 fits), `String(_, radix:, uppercase: true)`, leading `-` for negatives; binary grouped in 4s with spaces.
- New `Tests/CalcCoreTests/ResultFormatTests.swift`: `1÷3`→`1/3`, `2÷3`→`2/3`, `4÷3`→`1 1/3`, `-0.75`→`-3/4`, `0.1234567`→nil (denominator cap), `5`→fraction nil, `255`→`FF`/`377`/`1111 1111`, `-10`→`-A`, `0.5`→hex nil, `9999…9` (34 digits) → hex non-nil.

**App**
- `CalculatorView` display: small format badge under the result (`DEC` `FRAC` `HEX` `BIN` `OCT`) as a `Menu` of `ResultFormat.allCases`; choice stored in `Pref.resultFormat`. Primary line = `ResultFormat.format(...)` mapped through `−` for display, falling back to decimal with dimmed badge. VoiceOver label "Result format, Fraction".
- Binary may be long: allow `.lineLimit(2)` for binary only.
- Settings → Results: same picker + **Grouping separators** toggle (`InputNormalizer.display(result:locale:grouping:)` gains a `grouping: Bool = true` param → `.grouping(.never)`; one test).

## Task 5: More themes + sizes

- `App/Sources/Theme.swift`: add `id`, `name`, `colorScheme: ColorScheme`, `fontDesign: Font.Design`, `displaySize`, `keySize`; `displayFont` / `keyFont` become computed. Catalogue `static let all: [Theme]` + `static func named(_ id: String) -> Theme` (unknown → graphite):
  - **Graphite** (existing), **Paper** (light, ink keys), **Midnight** (navy + cyan), **Terminal** (black, green, `.monospaced`, small radius), **Bloom** (light pastel, large radius).
- `KeypadView`: replace hard-coded `.system(size: 30, …)` with `theme.keyFont`.
- Size setting `Pref.size` (Small / Medium / Large → scale 0.8 / 1.0 / 1.25 on `displaySize` + `keySize`).
- `RootView` and menu bar extra resolve theme from `Pref.theme` + size, inject `.environment(\.theme, …)` and `.preferredColorScheme(theme.colorScheme)` so the history sidebar matches. Menu bar keeps its smaller display size.
- Settings → Appearance: theme grid (swatch of background + operator + equals colors, name, checkmark, VoiceOver "Theme, Paper, selected") and Size picker.

## Task 6: Advanced settings (keypad, behavior, Mac)

Settings → Keypad & Behavior:
- **Show keypad** (`Pref.showKeypad`, default on) — `CalculatorView` hides `KeypadView`; Mac `minHeight` drops from 640 to ~300 when hidden.
- **Show recent results** (chips) toggle.
- **Copy result on =** — `CalculatorView .onChange(of: model.result)` → `Clipboard.copy(shown text)`.

Settings → Mac (`#if os(macOS)`):
- **Menu bar calculator** — `MenuBarExtra(isInserted: $showMenuBar)` bound to `@AppStorage`.
- **Global hotkey ⌥⌘=** — `@State private var hotkey: GlobalHotkey?` in the App, set/cleared in `WindowGroup … .onChange(of: hotkeyEnabled, initial: true)`; existing `isolated deinit` unregisters.
- Multiple windows already work after Task 1 (File ▸ New Window, ⌘N); no setting needed.

---

## Critical files

- `apple/CalcCore/Sources/CalcCore/HistoryStore.swift`, `CalculatorModel.swift`, `InputNormalizer.swift`, new `ResultFormat.swift`
- `apple/CalcCore/Tests/CalcCoreTests/HistoryStoreTests.swift`, `CalculatorModelTests.swift`, new `ResultFormatTests.swift`
- `apple/App/Sources/CalcusomeApp.swift`, `CalculatorView.swift`, `HistoryView.swift`, `KeypadView.swift`, `Theme.swift`, new `SettingsView.swift`, `Pref.swift`, `Clipboard.swift`
- `apple/App/project.yml`

Reuse: `ExactDecimal` `/` + `canonical` for fraction round-trip check; `InputNormalizer.display` for locale output; `HistoryStore.touch`/`live()` for new store ops; `GlobalHotkey` unchanged.

## Out of scope

Paywall/entitlements, unit & currency conversion, custom hotkey binding, alternate app icons, sound packs.

## Verification

1. `swift test --package-path apple/CalcCore` — all existing + new tests pass.
2. `cd apple/App && xcodegen && xcodebuild -scheme Calcusome -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` and the `generic/platform=iOS` build (same as CI).
3. Run the Mac app:
   - ⌘N twice → type different expressions in each window; `=` in one → chip appears in both, history sidebar updates in both.
   - `1÷3=` → set FRAC → `1/3`; `255=` → HEX `FF`, BIN `1111 1111`; `0.5=` in HEX → decimal with dimmed badge.
   - ⌘, → switch each theme (Paper flips sidebar to light), sizes S/M/L, hide keypad (window shrinks), toggle chips, copy-on-=, menu bar icon off/on, hotkey off (⌥⌘= no longer activates).
   - History: bookmark, copy result, Export… → open CSV in Numbers (labels with commas intact), Clear History keeps bookmarks; set Auto clear 1 day, set an entry's date back in a debug build or test → gone after relaunch.
4. iPad simulator: gear → settings sheet; open a second window via the app's multitasking menu; VoiceOver reads theme cells and format badge.
