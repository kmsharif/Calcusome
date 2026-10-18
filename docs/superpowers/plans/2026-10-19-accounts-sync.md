# Calcusome Accounts + Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Phase 3 of the product plan. People sign in with Apple or Google, and their calculation history syncs through Supabase. One account on two Apple devices keeps the same history, even after each device made changes offline.

**Architecture:** The app saves to the local SwiftData store first and syncs in the background, so it never waits on the network. Supabase holds a `history_entries` table protected by row-level security. A Postgres trigger enforces the merge rule on the server and stamps a server-side `synced_at` cursor. In `CalcCore`, a `SyncEngine` pushes rows flagged `needsPush`, then pulls everything newer than the cursor. It talks to the backend through a `HistoryRemote` protocol, so `swift test` can run two simulated devices against an in-memory fake. The app target implements `HistoryRemote` with `supabase-swift`, and also handles auth and the Realtime "something changed" ping.

**Tech Stack:** Swift 6.4, SwiftUI, SwiftData, Swift Testing, AuthenticationServices (Sign in with Apple), `supabase-swift` 2.x (app target only), Supabase CLI + Docker for the local backend, pgTAP via `supabase test db`.

**Spec:** [Calculator App: Product & Technical Plan](https://claude.ai/code/artifact/ef04c3fc-bdd9-473e-86b1-2009616d36f3). Relevant parts: the "Accounts, sync and history data" section (backend, local stores, field table, conflicts, accounts) and "Phased plan" item 3.

**Roadmap:** Phase 1 design (parallel) · Phase 2 local MVP ✅ · **Phase 3 this plan** · Phase 4 Android · Phase 5 premium + polish.

## Decisions (defaults taken, flag if wrong)

- **The sync cursor is a server-set `synced_at`, not the client's `updated_at`.** The spec says to pull "since last `updated_at`". That misses edits from a device that was offline: its `updated_at` is older than cursors other devices have already passed. Conflicts are still resolved by the client's `updated_at`, as the spec says.
- **A delete always wins.** The spec says last-write-wins (newest edit wins) on `updated_at`. On top of that, once `deleted_at` is set it is never cleared, even by a newer edit. Without this, an edit on device B after a delete on device A would bring the entry back, which the spec forbids.
- **Server-only cleanup is out.** No hard deletes from the server except account deletion, which cascades. Clients have no DELETE policy.
- **Clearing history deletes it everywhere.** Clear History and auto-clear delete entries on every signed-in device, because history is shared. Settings stay per device (the spec keeps settings sync out of v1). The Clear History dialog copy says so when the person is signed in.
- **Sign-out removes that account's history from the device.** Before removing, the app tries one last sync. If changes are still unsynced, the person must confirm. Entries made while signed out (`userID == nil`) are kept, and the next sign-in merges them into that account. That is the spec's "on first sign-in, local history merges into the account".
- **No paywall.** The spec puts sync behind a subscription, but RevenueCat comes in Phase 5. In this phase, sync is free for everyone.
- **Not in this plan:**
  - Named tapes. `tape_id` already syncs; the tapes feature gets its own plan.
  - Optional encryption on the device (still an open question in the spec).
  - Android (Phase 4).
  - Apple token revocation when an account is deleted. Apple requires this before App Store review but not for TestFlight. It needs an Edge Function holding the Sign in with Apple `.p8` key, so it gets its own follow-up.
  - Creating the hosted Supabase project.

## Global Constraints

- All MVP constraints still hold:
  - Decimal-only math. `spec/math-cases.json` and the engine grammar do not change.
  - Expressions and results are stored in canonical form.
  - Deletes are tombstones: `deleted_at` is set, the row is never removed.
  - Every mutation bumps `updatedAt`.
  - Every control has a VoiceOver label, and Reduce Motion is respected.
- The server table is `public.history_entries`. Its columns are the spec's fields in snake case (`id`, `user_id`, `device_id`, `expression`, `result`, `label`, `pinned`, `tape_id`, `created_at`, `updated_at`, `deleted_at`), plus `synced_at timestamptz`, which only the server writes.
- The local-only field is `HistoryEntry.needsPush: Bool = true`. It is never sent to the server.
- **Merge rule. The Swift code and the SQL trigger must agree exactly.**
  - The winner is the row with the strictly newer `updated_at`. On a tie, the existing row wins.
  - The result's `deleted_at` is the earlier of the two non-nil values.
  - `id`, `user_id`, `device_id` and `created_at` always come from the existing row.
- Timestamps made by `HistoryStore` are truncated to whole milliseconds, so they survive a trip through ISO 8601 JSON unchanged.
- The pull overlap is 60 seconds: each sync pulls from `cursor − 60s`. Re-applying a row is harmless.
- Push batches hold at most 500 rows. Pull pages hold 1000 rows.
- `CalcCore` stays free of third-party dependencies. Only the app target imports `Supabase`.
- Server limits (check constraints):
  - `char_length(expression) <= 1000`
  - `char_length(result) <= 200`
  - `char_length(label) <= 200`
  - `char_length(device_id) <= 64`
- The OAuth redirect is `calcusome://auth-callback`. The bundle ID is still `com.calcusome.app`, and is also the Apple provider `client_id`.
- The anon key is public by design; row-level security protects the data. Never ship the `service_role` key in the app or the repo.

## Review Focus

1. **Two devices edit the same entry offline:** A deletes it, then B pins it later. After both sync, the entry is deleted on both devices and on the server. Covered by `deleteBeatsNewerEdit` (Task 3) and pgTAP `older tombstone still deletes` (Task 1).
2. **Sign-in on a device that already has local history, into an account that has history from another device.** After sign-in, both sets of history appear on both devices, with no duplicates and nothing lost. Covered by `signInMergesBothSides` (Task 3).
3. **An edit while a push is in flight** (the person pins an entry during sync) stays pending and goes up on the next sync. It is not marked synced. Covered by `editDuringPushStaysPending` (Task 3).
4. **A device's own change comes back through Realtime or the pull overlap.** It must not set `needsPush` again; otherwise two devices would bounce one row back and forth forever. Covered by `applyOwnEchoIsNoOp` (Task 2) and `secondSyncPushesNothing` (Task 3).
5. **Sign-out with unsynced changes** (offline, then sign out). The app warns with the count and deletes nothing silently. Covered by `pendingCountIgnoresSignedOutRows` (Task 2) and the dialog in Task 5.

---

## File Structure

```
supabase/config.toml                              supabase init + auth providers (Task 1)
supabase/migrations/20261019000000_history.sql    table, RLS, merge trigger, realtime, delete_my_account
supabase/tests/history_test.sql                   pgTAP
.github/workflows/apple.yml                       + db job
apple/CalcCore/Sources/CalcCore/
  HistoryEntry.swift                              + needsPush, init(remote), apply(remote)
  RemoteEntry.swift                               wire row + merge rule (Task 2)
  HistoryStore.swift                              + userID, sync hooks (Task 2)
  SyncEngine.swift                                HistoryRemote protocol + push/pull loop (Task 3)
apple/CalcCore/Tests/CalcCoreTests/
  HistorySyncTests.swift                          store sync API (Task 2)
  SyncEngineTests.swift                           FakeRemote, two-device tests (Task 3)
apple/App/project.yml                             + supabase-swift package, entitlements
apple/App/Calcusome.entitlements                  Sign in with Apple
apple/App/Sources/Sync/SupabaseConfig.swift       URL + anon key
apple/App/Sources/Sync/SupabaseHistoryRemote.swift
apple/App/Sources/Sync/Account.swift              auth state, sign in/out/delete, realtime
apple/App/Sources/AccountSection.swift            Settings UI (Task 5)
apple/App/Sources/CalcusomeApp.swift              wire Account
apple/App/Sources/SettingsView.swift              + Account section
apple/App/Sources/HistoryView.swift               Clear History copy
```

---

### Task 1: Supabase backend with the merge rule enforced on the server

**Files:**
- Create: `supabase/config.toml` (via `supabase init`), `supabase/migrations/20261019000000_history.sql`, `supabase/tests/history_test.sql`
- Modify: `.github/workflows/apple.yml`, `.gitignore` (add `supabase/.temp/`, `supabase/.branches/`)

**Interfaces:**
- Produces:
  - Table `public.history_entries`.
  - Function `public.delete_my_account() returns void`, callable by `authenticated` only.
  - Realtime publication on the table.
  - Locally: API at `http://127.0.0.1:54321`, with the anon key printed by `supabase status`.

- [ ] **Step 1: Install the CLI and init.** Run `brew install supabase/tap/supabase`, then `supabase init` at the repo root.

- [ ] **Step 2: Configure auth in `supabase/config.toml`.**
  - `[auth]`: `site_url = "calcusome://auth-callback"` and `additional_redirect_urls = ["calcusome://auth-callback"]`.
  - `[auth.external.apple]`: `enabled = true` and `client_id = "com.calcusome.app"`. No secret is needed for the native ID-token flow.
  - `[auth.external.google]`: `enabled = true`, `client_id = "env(GOOGLE_CLIENT_ID)"` and `secret = "env(GOOGLE_CLIENT_SECRET)"`.
  - Add a `supabase/.env.example` naming those two variables, without values.

- [ ] **Step 3: Write the failing pgTAP tests** in `supabase/tests/history_test.sql`.
  - Setup: `begin; select plan(N);`. Insert two users into `auth.users` (ids `a`/`b`). Act as a user with `set local role authenticated` plus `set local request.jwt.claims = '{"sub":"<uuid>"}'`. End with `select * from finish(); rollback;`.
  - Assertions:
    - `A inserts own row`: `lives_ok`.
    - `A cannot insert as B`: `throws_ok` when the insert carries `user_id = b`.
    - `B sees none of A's rows`: `is(count, 0)`.
    - `older update ignored`: A updates with `updated_at` 1s earlier and a new label. The label and `synced_at` are unchanged.
    - `newer update applied`: the label changes and `synced_at` increases.
    - `older tombstone still deletes`: A sends `deleted_at` with an older `updated_at`. Afterwards `deleted_at` is set, while `label` and `updated_at` keep the newer row's values.
    - `tombstone is sticky`: a newer update with `deleted_at = null` leaves `deleted_at` set.
    - `identity columns immutable`: an update setting `device_id`, `created_at` and `user_id` changes none of them.
    - `long expression rejected`: `throws_ok` for a 1001-character expression.
    - `anon cannot delete accounts`: `throws_ok` calling `delete_my_account()` as `anon`.
    - `delete_my_account removes user and rows`: as A, call it. Afterwards `auth.users` has no row `a` and `history_entries` has no rows for A.

- [ ] **Step 4: Run and see it fail.** Run `supabase start && supabase test db`.
Expected: FAIL, `relation "history_entries" does not exist`.

- [ ] **Step 5: Write the migration.**
  - The table:
    - Columns are as in Global Constraints. `user_id uuid not null default auth.uid() references auth.users on delete cascade`. `pinned boolean not null default false`. `synced_at timestamptz not null default clock_timestamp()`.
    - Add the four check constraints.
    - Add an index on `(user_id, synced_at)`.
  - Turn on RLS, with `select`/`insert`/`update` policies `using / with check ((select auth.uid()) = user_id)`. Add no delete policy.
  - `alter publication supabase_realtime add table public.history_entries;`
  - `delete_my_account`: `language sql security definer set search_path = ''`, body `delete from auth.users where id = auth.uid();`. Revoke execute from `public, anon` and grant it to `authenticated`.
  - The merge trigger, `before insert or update ... for each row`. This is the algorithm:

```sql
create function public.history_merge() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id; new.device_id := old.device_id; new.created_at := old.created_at;
    if new.updated_at <= old.updated_at then
      if new.deleted_at is null or old.deleted_at is not null then
        return null;  -- stale edit: skip the row (no WAL write, no Realtime event)
      end if;
      -- stale edit carrying a delete: keep the newer content, take the tombstone
      new.expression := old.expression; new.result := old.result; new.label := old.label;
      new.pinned := old.pinned; new.tape_id := old.tape_id; new.updated_at := old.updated_at;
    else
      new.deleted_at := least(old.deleted_at, new.deleted_at);  -- least() skips nulls
    end if;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end $$;
```

- [ ] **Step 6: Run the tests and see them pass.** Run `supabase db reset && supabase test db`.
Expected: `All tests successful`.

- [ ] **Step 7: Add a CI job** `db` to `.github/workflows/apple.yml`. It runs on `ubuntu-latest` with these steps: `actions/checkout@v4`, `supabase/setup-cli@v1` (`version: latest`), `supabase start`, `supabase test db`.

- [ ] **Step 8: Commit.**

```bash
git add supabase .github/workflows/apple.yml .gitignore
git commit -m "feat: Supabase history table with RLS and server-side merge rule"
```

---

### Task 2: Store-side sync support (wire row, merge rule, flags)

**Files:**
- Create: `apple/CalcCore/Sources/CalcCore/RemoteEntry.swift`
- Modify: `apple/CalcCore/Sources/CalcCore/HistoryEntry.swift`, `apple/CalcCore/Sources/CalcCore/HistoryStore.swift`
- Test: `apple/CalcCore/Tests/CalcCoreTests/HistorySyncTests.swift`

**Interfaces:**
- Produces:
  - `public struct RemoteEntry: Codable, Sendable, Equatable`. Its fields are `id: UUID, userID: UUID, deviceID: String, expression: String, result: String, label: String?, pinned: Bool, tapeID: UUID?, createdAt: Date, updatedAt: Date, deletedAt: Date?, syncedAt: Date?`. Its `CodingKeys` are snake case.
  - `public static func merged(existing: RemoteEntry, incoming: RemoteEntry) -> RemoteEntry`. It applies the merge rule and keeps `existing.syncedAt`.
  - `HistoryEntry.needsPush: Bool = true`, `convenience init(_ remote: RemoteEntry)` and `func apply(_ remote: RemoteEntry)`. `apply` copies every field except `id`.
  - On `HistoryStore`:
    - `public var userID: UUID?`
    - `public var onLocalChange: (() -> Void)?`
    - `public func pendingPush(limit: Int) throws -> [RemoteEntry]`
    - `public func markPushed(_ pushed: [RemoteEntry]) throws`
    - `public func apply(_ remote: [RemoteEntry]) throws`
    - `public func adopt(userID: UUID) throws`
    - `public func purge(userID: UUID) throws`
    - `public func pendingCount() throws -> Int`

- [ ] **Step 1: Write the failing tests** in `HistorySyncTests.swift`. Reuse `TestClock` from `HistoryStoreTests`, and add a helper `remote(_ e: HistoryEntry, ...)` that builds a `RemoteEntry` with overrides.

```swift
@Test func addStampsUserIDWhenSignedIn()       // store.userID = u; add → e.userID == u, e.needsPush
@Test func timestampsAreWholeMilliseconds()    // clock.now = Date(timeIntervalSince1970: 1_000_000.123456)
                                               // → e.createdAt.timeIntervalSince1970 == 1_000_000.123
@Test func remoteEntryJSONRoundTrip()          // .custom date strategy, ISO8601DateFormatter [.withInternetDateTime,
                                               // .withFractionalSeconds]; store-made row encodes and decodes == original;
                                               // JSON contains "user_id", "label":null, "deleted_at":null, no "synced_at"
@Test func mergeNewerWins()                    // merged(existing: t1 label "a", incoming: t2 label "b").label == "b"
@Test func mergeTieKeepsExisting()             // same updatedAt → existing's label
@Test func mergeTombstoneSticky()              // existing deleted at t1, incoming t2 not deleted → deletedAt == t1
@Test func mergeOlderTombstoneWins()           // existing t2 alive, incoming t1 deleted → deletedAt == t1, updatedAt == t2
@Test func mergeKeepsIdentity()                // incoming with other deviceID/createdAt → existing's kept
@Test func pendingPushOnlySignedInDirtyRows()  // nil-userID rows excluded; after markPushed → pendingPush empty
@Test func markPushedSkipsRowsEditedSince()    // snapshot, then setPinned, markPushed(snapshot) → still pending
@Test func applyInsertsUnknown()               // apply([r]) → all() contains r.id, needsPush == false
@Test func applyNewerRemoteWins()              // local label "a" t1 clean; remote "b" t2 → "b", needsPush false
@Test func applyOlderRemoteKeepsLocalAndRepushes() // local t2 dirty, remote t1 → local kept, needsPush true
@Test func applyRemoteDeleteHidesEntry()       // remote deletedAt → not in recent/all/search
@Test func applyOwnEchoIsNoOp()                // markPushed then apply(same row with syncedAt) → needsPush false, fields equal
@Test func applyDoesNotFireOnLocalChange()     // counter on onLocalChange stays 0 after apply; add → 1
@Test func applyBumpsRevision()
@Test func adoptClaimsLocalEntries()           // two nil-userID rows (one tombstoned) → both userID u, needsPush true
@Test func purgeRemovesOnlyThatAccount()       // rows for u, v and nil → purge(u) leaves v and nil; store.userID == nil
@Test func pendingCountIgnoresSignedOutRows()
```

- [ ] **Step 2: Run them and see them fail.** Run `swift test --package-path apple/CalcCore --filter HistorySyncTests`.
Expected: compile error, `cannot find 'RemoteEntry' in scope`.

- [ ] **Step 3: Implement `RemoteEntry.swift`.**
  - Write a custom `encode(to:)`. It always encodes `label`, `tape_id` and `deleted_at`, as an explicit `null` when nil, because PostgREST would leave an omitted column unchanged and a removed label would never clear on the server. It never encodes `synced_at`. Decoding is synthesized.
  - Add `init(_ entry: HistoryEntry, fallbackUserID: UUID? = nil)`. It uses `entry.userID ?? fallbackUserID` and traps if both are nil. `pendingPush` passes no fallback. `apply` passes `remote.userID`.

- [ ] **Step 4: Change `HistoryEntry`.**
  - Add `public var needsPush: Bool = true`. Declare it with a default value so SwiftData's automatic lightweight migration adds the column.
  - Add `convenience init(_ remote:)` and `apply(_:)`.
  - Update the doc comment: `needsPush` is local only.

- [ ] **Step 5: Change `HistoryStore`.**
  - In `init`, wrap the clock: `now` → truncate down to whole milliseconds.
  - `add` stamps `userID`.
  - `save()` gets a `local: Bool = true` parameter. Local saves set `needsPush` on the touched rows (in `add`, `touch` and the `deleteUnpinned` loop) and call `onLocalChange`. `apply` saves with `local: false`.
  - Make `apply` a single loop. Look up the local row by `id`.
    - Missing → insert `HistoryEntry(remote)` with `needsPush = false`.
    - Present → `m = RemoteEntry.merged(existing: RemoteEntry(local, fallbackUserID: remote.userID), incoming: remote)` with `m.syncedAt = remote.syncedAt`, then `local.apply(m)` and `local.needsPush = (m != remote)`.
  - `markPushed` clears `needsPush` only where `updatedAt` and `deletedAt` still equal the pushed snapshot.
  - `adopt` sets `self.userID` and claims every `userID == nil` row, setting `needsPush = true`.
  - `purge` uses `context.delete` (a real local delete; the server keeps the data) on every row with that `userID`, then sets `self.userID = nil`.

- [ ] **Step 6: Run the tests.** Run `swift test --package-path apple/CalcCore`.
Expected: all suites pass, including the existing `HistoryStoreTests`.

- [ ] **Step 7: Commit.**

```bash
git add apple/CalcCore
git commit -m "feat: history store sync hooks with shared merge rule"
```

---

### Task 3: SyncEngine (push, paged pull, cursor) proven with two simulated devices

**Files:**
- Create: `apple/CalcCore/Sources/CalcCore/SyncEngine.swift`
- Test: `apple/CalcCore/Tests/CalcCoreTests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: the Task 2 `HistoryStore` sync API and `RemoteEntry.merged`.
- Produces:
  - The backend protocol:
    ```swift
    public protocol HistoryRemote: Sendable {
        func push(_ entries: [RemoteEntry]) async throws
        func pull(from cursor: Date?, limit: Int) async throws -> [RemoteEntry]  // synced_at >= cursor, ascending
    }
    ```
  - `@MainActor @Observable public final class SyncEngine` with:
    - `init(store: HistoryStore, remote: any HistoryRemote, cursorKey: String, defaults: UserDefaults = .standard)`
    - `public enum Status: Equatable { case idle, syncing, failed(String) }`
    - `public private(set) var status: Status`
    - `public private(set) var lastSynced: Date?`
    - `public func sync() async` (never throws; puts the error in `status`)
    - `public func scheduleSync(after delay: Duration = .seconds(1))` (debounced)

- [ ] **Step 1: Write the failing tests**, with a `FakeRemote` in the test file.
  - `FakeRemote` is an `actor` that keeps rows by id.
  - `push` merges each row with `RemoteEntry.merged`, or inserts it if new. It sets `syncedAt` from a counter clock, and skips the update when the merge leaves the stored row unchanged, the same as the trigger.
  - `pull` filters `syncedAt >= cursor`, sorts ascending and applies the limit.
  - Knobs: `failNextPush: Bool`, `pageLimit: Int?` (overrides the limit), `onPush: (@Sendable () async -> Void)?`.
  - Each "device" is its own `HistoryStore.inMemory(deviceID:)`, plus its own `UserDefaults(suiteName: UUID().uuidString)!` and `SyncEngine`, all sharing one fake.

```swift
@Test func pushesPendingAndClearsFlag()       // add, sync → fake has row, store.pendingCount() == 0, status == .idle
@Test func pullsOtherDeviceEntries()          // A add + sync; B sync → B.all() has A's row with deviceID "A"
@Test func twoDevicesConvergeAfterOfflineEdits()
    // A, B synced on shared row r. Offline: A labels r "Rent" (t+1); B pins r (t+2); A adds x; B adds y.
    // sync A, B, A → both stores' live rows equal as [RemoteEntry] sets (ignoring syncedAt); r.pinned, r.label == nil
    // (B's newer edit wins whole-row — LWW is per row, not per field; matches the spec)
@Test func deleteBeatsNewerEdit()             // A deletes r (t+1), B pins r (t+2), sync A, B, A → r deleted on both
@Test func signInMergesBothSides()            // A has 2 synced rows; B has 1 local nil-userID row;
                                              // B.adopt(u); sync B, A → both have 3 live rows, ids unique
@Test func failedPushKeepsPending()           // failNextPush → status == .failed, pendingCount() == 1; sync again → 0
@Test func editDuringPushStaysPending()       // onPush pins the entry on the main actor → after sync, pendingCount() == 1
@Test func pullPaginates()                    // A pushes 5 rows; pageLimit 2; B sync → 5 rows
@Test func cursorPersistsAcrossEngines()      // B syncs; new engine on same defaults → pull called with from == saved − 60s
@Test func secondSyncPushesNothing()          // sync twice with no edits → fake push count unchanged on 2nd
@Test func concurrentSyncCallsDoNotOverlap()  // async let two sync() calls → pushes in sequence, no duplicate rows, pending 0
```

- [ ] **Step 2: Run them and see them fail.** Run `swift test --package-path apple/CalcCore --filter SyncEngineTests`.
Expected: compile error, `cannot find 'SyncEngine' in scope`.

- [ ] **Step 3: Implement `SyncEngine.swift`.** The `sync()` algorithm:
  1. If a sync is already running, set `rerun = true` and return. Otherwise set `status = .syncing`.
  2. Push. Keep a `pushed: Set<UUID>` for this round. Repeat: take `batch = store.pendingPush(limit: 500)` minus any ids in `pushed`, and stop if it is empty. Otherwise `remote.push(batch)`, `store.markPushed(batch)` and add the ids to `pushed`. A row edited mid-push stays pending; its edit called `onLocalChange`, which schedules the next sync.
  3. Pull. Start at `from = savedCursor.map { $0 − 60 }`, then loop:
     - `page = remote.pull(from: from, limit: 1000)` and `store.apply(page)`.
     - Save the cursor as the largest `syncedAt` seen.
     - Stop if `page.count < 1000` or the cursor did not move. Otherwise set `from` to the new cursor.
  4. Finish with `status = .idle` and `lastSynced = .now`. If `rerun` is set, clear it and loop back to step 2.
  5. On any error: `status = .failed(error.localizedDescription)`, then `scheduleSync(after: .seconds(30))` with `// ponytail: fixed 30s retry, add backoff if a dead server sees request storms`.
  - Store the cursor in `defaults` under `cursorKey` as a `Double` (`timeIntervalSince1970`).
  - `scheduleSync` cancels any pending scheduled `Task`, sleeps for `delay`, then calls `sync()`.

- [ ] **Step 4: Run all the tests.** Run `swift test --package-path apple/CalcCore`.
Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add apple/CalcCore
git commit -m "feat: sync engine with paged pull and server cursor"
```

---

### Task 4: Supabase client, auth and Realtime in the app

**Files:**
- Create: `apple/App/Sources/Sync/SupabaseConfig.swift`, `apple/App/Sources/Sync/SupabaseHistoryRemote.swift`, `apple/App/Sources/Sync/Account.swift`, `apple/App/Calcusome.entitlements`
- Modify: `apple/App/project.yml`, `apple/App/Sources/CalcusomeApp.swift`

**Interfaces:**
- Consumes: `HistoryRemote`, `SyncEngine` and `HistoryStore`, with the sync API from Tasks 2–3.
- Produces, for Task 5:
  - `@MainActor @Observable final class Account` with:
    - `enum State: Equatable { case signedOut, signedIn(email: String?, userID: UUID) }`
    - `private(set) var state: State`
    - `private(set) var sync: SyncEngine?`
    - `func signInWithApple(_ result: Result<ASAuthorization, Error>) async throws`
    - `func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest)`
    - `func signInWithGoogle() async throws`
    - `func signOut(discardingUnsynced: Bool = false) async throws`
    - `func deleteAccount() async throws`
  - `enum AccountError: LocalizedError { case unsynced(Int) }`

- [ ] **Step 1: Update `project.yml`.**
  - `packages: Supabase: url: https://github.com/supabase/supabase-swift, from: "2.0.0"`. Pin to the newest 2.x at implementation time, and check the call names below against that version's README.
  - Add the target dependency `- package: Supabase, product: Supabase`.
  - Add `entitlements: { path: Calcusome.entitlements, properties: { com.apple.developer.applesignin: [Default] } }`.
  - Add `DEVELOPMENT_TEAM: ""` with a comment: set it locally, because Sign in with Apple needs a real team.

- [ ] **Step 2: Create `SupabaseConfig.swift`.**
  - `enum SupabaseConfig { static let url: URL; static let anonKey: String }`.
  - Use the local `supabase status` values (`http://127.0.0.1:54321`).
  - Comment: replace with the hosted project before TestFlight. The anon key is public, and RLS guards the data.

- [ ] **Step 3: Implement `SupabaseHistoryRemote: HistoryRemote`.**
  - Init with `client: SupabaseClient`.
  - `push`: `client.from("history_entries").upsert(entries, onConflict: "id").execute()`.
  - `pull`: `client.from("history_entries").select().gte("synced_at", value: cursor)` (skip the filter when `cursor` is nil) `.order("synced_at").limit(limit).execute().value`.

- [ ] **Step 4: Implement `Account`.**
  - It owns `client = SupabaseClient(supabaseURL:supabaseKey:)`.
  - In `init(store:)`, start a `Task` over `client.auth.authStateChanges`:
    - `.initialSession` or `.signedIn` with a session → `didSignIn(session.user)`.
    - `.signedOut` → `tearDown()`.
  - `didSignIn`:
    - `store.adopt(userID: user.id)`.
    - Create `sync = SyncEngine(store:, remote: SupabaseHistoryRemote(client:), cursorKey: "syncCursor.\(user.id)")`.
    - Set `store.onLocalChange = { [weak self] in self?.sync?.scheduleSync() }`.
    - Subscribe to the Realtime channel `"history"` with `postgresChange(AnyAction.self, schema: "public", table: "history_entries", filter: .eq("user_id", value: user.id))`. On each event, call `scheduleSync(after: .zero)`. The event is only a ping: the pull fetches the actual data.
    - Set `state = .signedIn(email: user.email, userID: user.id)`, then `await sync?.sync()`.
  - Apple sign-in:
    - `configureAppleRequest` sets `requestedScopes = [.email]` and `nonce = SHA256(raw)` with CryptoKit, where `raw` is 32 random bytes as hex stored in `pendingNonce`.
    - `signInWithApple` takes the `ASAuthorizationAppleIDCredential.identityToken` and calls `client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken:, nonce: pendingNonce))`.
    - `ASAuthorizationError.canceled` returns quietly.
  - Google sign-in: `client.auth.signInWithOAuth(provider: .google, redirectTo: URL(string: "calcusome://auth-callback"))`. It uses `ASWebAuthenticationSession`, so no URL type registration is needed.
  - `signOut`:
    - `await sync?.sync()`.
    - If `!discardingUnsynced` and `store.pendingCount() > 0`, throw `.unsynced(n)`.
    - Otherwise `client.auth.signOut()` and `tearDown()`.
  - `deleteAccount`: `client.rpc("delete_my_account").execute()`, then try `client.auth.signOut()` and ignore its error, because the user no longer exists. Then `tearDown()`.
  - `tearDown`:
    - Unsubscribe from the channel.
    - `store.purge(userID:)`.
    - Remove the defaults key `syncCursor.<uid>`.
    - Set `store.onLocalChange = nil`, `sync = nil` and `state = .signedOut`.
    - Make it idempotent: return early when already signed out. The `.signedOut` auth event fires after the app's own `signOut()` and would otherwise run it twice.

- [ ] **Step 5: Wire it in `CalcusomeApp`.**
  - Hold `account = Account(store: store)` beside `store`, and pass it with `.environment(account)` to `RootView`, `SettingsView` and `MenuBarCalculator`.
  - In `RootView`'s existing `scenePhase == .active` handler, add `account.sync?.scheduleSync(after: .zero)`.

- [ ] **Step 6: Build both platforms.** Run `cd apple/App && xcodegen && xcodebuild -scheme Calcusome -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build && xcodebuild -scheme Calcusome -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`.
Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 7: Commit.**

```bash
git add apple/App
git commit -m "feat: Supabase auth, history remote and realtime wiring"
```

---

### Task 5: Account UI in Settings

**Files:**
- Create: `apple/App/Sources/AccountSection.swift`
- Modify: `apple/App/Sources/SettingsView.swift` (first `Section`), `apple/App/Sources/HistoryView.swift:139-142` (Clear History dialog)

**Interfaces:**
- Consumes: `Account` from the environment (Task 4).

- [ ] **Step 1: Build `AccountSection: View`**, as `Section("Account")`. The exact copy:
  - **Signed out:**
    - `SignInWithAppleButton(.signIn, onRequest: account.configureAppleRequest, onCompletion: …)`, with `.signInWithAppleButtonStyle` set to `.white` in dark mode and `.black` otherwise, and `.frame(height: 36)`.
    - `Button("Continue with Google")`.
    - Footer: "Sign in to keep your history in step on all your devices. Without an account, history stays on this device."
  - **Signed in:**
    - `LabeledContent("Signed in as", value: email ?? "Apple ID")`.
    - A status line from `account.sync`:
      - `.syncing` → "Syncing…"
      - `.idle` → "Synced \(lastSynced, format: .relative(presentation: .named))"
      - `.failed` → "Can't reach the server. Will retry."
    - Then "· \(n) waiting" when `pendingCount() > 0`.
    - `Button("Sign Out")`.
    - `Button("Delete Account…", role: .destructive)`.
  - **Dialogs:**
    - Sign out with unsynced changes (catch `AccountError.unsynced(n)`): title "Sign out without syncing?", message "\(n) changes on this device haven't synced and will be lost.", buttons "Sign Out Anyway" (destructive, calls `signOut(discardingUnsynced: true)`) and "Cancel".
    - Delete account: title "Delete your account?", message "This deletes your account and its history from every device. This can't be undone.", buttons "Delete Account" (destructive) and "Cancel".
    - Any other error: alert "Couldn't sign in" or "Couldn't delete account", with `error.localizedDescription`.

- [ ] **Step 2: Insert `AccountSection()` as the first section** of `SettingsView`'s `Form`.

- [ ] **Step 3: Update the Clear History dialog copy.** In `historyTools`, read `Account` from the environment. When signed in, the message is "Bookmarked calculations are kept. This clears history on all your signed-in devices." When signed out, it stays "Bookmarked calculations are kept."

- [ ] **Step 4: Build both platforms.** Use the same command as Task 4 Step 6.
Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 5: Run a VoiceOver pass on the Mac.** Each account control reads its visible title. The sync status line reads as one element (use `.accessibilityElement(children: .combine)`).

- [ ] **Step 6: Commit.**

```bash
git add apple/App/Sources
git commit -m "feat: account section with sign-in, sync status, sign-out and deletion"
```

---

### Task 6: Exit check, one account on two Apple devices

This is a manual run against the local backend. It is the spec's exit criterion: "one account, two Apple devices, history in step after offline edits on both."

- [ ] **Step 1: Set up.**
  - Run `supabase start`, with `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` exported if you test Google.
  - Set `DEVELOPMENT_TEAM` locally.
  - Run the Mac app, plus the iPad simulator, which reaches `127.0.0.1` on the Mac.
- [ ] **Step 2: Merge on sign-in.**
  - Make two calculations on the Mac and one on the iPad while signed out.
  - Sign in on the Mac, then on the iPad with the same Apple ID.
  - Expected: both devices show 3 entries, with none duplicated.
- [ ] **Step 3: Live sync.** On the Mac, compute `500×64`. Expected: it appears on the iPad within 5 seconds, with no relaunch.
- [ ] **Step 4: Offline edits on both.**
  - Run `supabase stop` (both devices are now "offline").
  - On the Mac, label entry X "Rent" and add a new entry.
  - On the iPad, delete entry X and bookmark entry Y.
  - Settings shows "Can't reach the server" and "· N waiting".
  - Run `supabase start` and reopen both apps (to trigger scene-active).
  - Expected: both devices show the same entries. X is gone, Y is bookmarked, and the new entry is present.
- [ ] **Step 5: Sign-out guard.**
  - Run `supabase stop`, add an entry on the Mac, then Sign Out.
  - Expected: the "Sign out without syncing?" dialog appears with a count of 1. Cancel keeps everything.
- [ ] **Step 6: Delete account.**
  - Run `supabase start` and choose Delete Account on the Mac.
  - Expected: the Mac is signed out with its synced history removed. After relaunch, the iPad is signed out too, because its refresh token is rejected. Signing in again on either device gives an empty account.
- [ ] **Step 7: Record results.** Tick these steps in this plan and commit: `git commit -am "docs: Phase 3 exit check results"`.
