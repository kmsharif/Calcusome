import Foundation
import Testing
@testable import CalcCore

struct Boom: Error {}

/// In-memory stand-in for the Supabase table, including the server's merge trigger.
actor FakeRemote: HistoryRemote {
    private var rows: [UUID: RemoteEntry] = [:]
    private var counter = 0
    private var failNextPush = false
    private var pageLimit: Int?
    private var onPush: (@Sendable () async -> Void)?
    private var inFlight = 0

    private(set) var pushCount = 0
    private(set) var maxInFlight = 0
    private(set) var pullFroms: [Date?] = []

    func failNext() { failNextPush = true }
    func setPageLimit(_ n: Int?) { pageLimit = n }
    func setOnPush(_ f: (@Sendable () async -> Void)?) { onPush = f }
    func rowCount() -> Int { rows.count }

    private func stamp() -> Date {
        counter += 1
        return Date(timeIntervalSince1970: 2_000_000 + Double(counter))
    }

    func push(_ entries: [RemoteEntry]) async throws {
        pushCount += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        await onPush?()
        if failNextPush {
            failNextPush = false
            throw Boom()
        }
        for incoming in entries {
            guard let stored = rows[incoming.id] else {
                var row = incoming
                row.syncedAt = stamp()
                rows[incoming.id] = row
                continue
            }
            var merged = RemoteEntry.merged(existing: stored, incoming: incoming)
            merged.syncedAt = stored.syncedAt
            if merged == stored { continue }  // the trigger skips a no-op row, so synced_at stays put
            merged.syncedAt = stamp()
            rows[incoming.id] = merged
        }
    }

    func pull(from cursor: Date?, limit: Int) async throws -> [RemoteEntry] {
        pullFroms.append(cursor)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        let hits = rows.values.filter { r in cursor.map { r.syncedAt! >= $0 } ?? true }
        return Array(hits.sorted { $0.syncedAt! < $1.syncedAt! }.prefix(pageLimit ?? limit))
    }
}

@MainActor struct SyncEngineTests {
    let clock = TestClock()
    let remote = FakeRemote()
    let u = UUID()

    /// One simulated device: its own store, defaults and engine, all sharing `remote` and `clock`.
    struct Device {
        let store: HistoryStore
        let engine: SyncEngine
        let defaults: UserDefaults
    }

    func device(_ id: String, signedIn: Bool = true, defaults: UserDefaults? = nil) throws -> Device {
        let clock = clock
        let store = try HistoryStore.inMemory(deviceID: id, now: { clock.now })
        if signedIn { store.userID = u }
        let defaults = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        return Device(store: store, engine: SyncEngine(store: store, remote: remote, cursorKey: "cursor", defaults: defaults), defaults: defaults)
    }

    /// Live rows as the server would see them, minus the sync cursor, in a stable order.
    func live(_ d: Device) throws -> [RemoteEntry] {
        try d.store.all().map { var r = RemoteEntry($0); r.syncedAt = nil; return r }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    @Test func pushesPendingAndClearsFlag() async throws {
        let a = try device("A")
        try a.store.add(expression: "1+1", result: "2")
        await a.engine.sync()
        #expect(await remote.rowCount() == 1)
        #expect(try a.store.pendingCount() == 0)
        #expect(a.engine.status == .idle)
        #expect(a.engine.lastSynced != nil)
    }

    @Test func pullsOtherDeviceEntries() async throws {
        let a = try device("A"), b = try device("B")
        try a.store.add(expression: "1+1", result: "2")
        await a.engine.sync()
        await b.engine.sync()
        let all = try b.store.all()
        #expect(all.count == 1)
        #expect(all.first?.deviceID == "A")
        #expect(try b.store.pendingCount() == 0)
    }

    @Test func twoDevicesConvergeAfterOfflineEdits() async throws {
        let a = try device("A"), b = try device("B")
        let r = try a.store.add(expression: "1+1", result: "2")
        await a.engine.sync()
        await b.engine.sync()
        let rB = try #require(b.store.all().first)

        clock.advance()
        try a.store.setLabel(r, "Rent")
        clock.advance()
        try b.store.setPinned(rB, true)
        try a.store.add(expression: "2+2", result: "4")
        try b.store.add(expression: "3+3", result: "6")

        await a.engine.sync()
        await b.engine.sync()
        await a.engine.sync()

        let liveA = try live(a), liveB = try live(b)
        #expect(liveA == liveB)
        #expect(liveA.count == 3)
        #expect(try a.store.pendingCount() == 0)
        #expect(try b.store.pendingCount() == 0)
        let shared = try #require(liveA.first { $0.id == r.id })
        #expect(shared.pinned)
        #expect(shared.label == nil)  // B's newer edit wins the whole row
    }

    @Test func deleteBeatsNewerEdit() async throws {
        let a = try device("A"), b = try device("B")
        let r = try a.store.add(expression: "1+1", result: "2")
        await a.engine.sync()
        await b.engine.sync()
        let rB = try #require(b.store.all().first)

        clock.advance()
        try a.store.delete(r)
        clock.advance()
        try b.store.setPinned(rB, true)

        await a.engine.sync()
        await b.engine.sync()
        await a.engine.sync()

        #expect(try a.store.all().isEmpty)
        #expect(try b.store.all().isEmpty)
    }

    @Test func signInMergesBothSides() async throws {
        let a = try device("A"), b = try device("B", signedIn: false)
        try a.store.add(expression: "1+1", result: "2")
        try a.store.add(expression: "2+2", result: "4")
        await a.engine.sync()
        try b.store.add(expression: "3+3", result: "6")
        try b.store.adopt(userID: u)

        await b.engine.sync()
        await a.engine.sync()

        let liveA = try live(a), liveB = try live(b)
        #expect(liveA.count == 3)
        #expect(liveA == liveB)
        #expect(Set(liveA.map(\.id)).count == 3)
    }

    @Test func failedPushKeepsPending() async throws {
        let a = try device("A")
        try a.store.add(expression: "1+1", result: "2")
        await remote.failNext()
        await a.engine.sync()
        guard case .failed = a.engine.status else { Issue.record("status \(a.engine.status)"); return }
        #expect(try a.store.pendingCount() == 1)
        await a.engine.sync()
        #expect(try a.store.pendingCount() == 0)
        #expect(a.engine.status == .idle)
    }

    @Test func editDuringPushStaysPending() async throws {
        let a = try device("A")
        try a.store.add(expression: "1+1", result: "2")
        let store = a.store, clock = clock
        await remote.setOnPush {
            await MainActor.run {
                clock.advance()
                let e = try! store.recent(limit: 1).first!
                try! store.setPinned(e, true)
            }
        }
        await a.engine.sync()
        #expect(try a.store.pendingCount() == 1)
        #expect(try a.store.pendingPush(limit: 10).first?.pinned == true)
    }

    @Test func pullPaginates() async throws {
        let a = try device("A"), b = try device("B")
        for i in 0..<5 { try a.store.add(expression: "\(i)+1", result: "\(i + 1)") }
        await a.engine.sync()
        await remote.setPageLimit(2)
        await b.engine.sync()
        #expect(try b.store.all().count == 5)
    }

    @Test func pullAdvancesPastFullOverlapWindow() async throws {
        let a = try device("A"), b = try device("B")
        for i in 0..<5 { try a.store.add(expression: "\(i)+1", result: "\(i + 1)") }
        await a.engine.sync()
        await remote.setPageLimit(2)
        await b.engine.sync()
        #expect(try b.store.all().count == 5)

        try a.store.add(expression: "9+9", result: "18")
        await a.engine.sync()
        await b.engine.sync()  // all 6 rows sit inside the 60s overlap, so the first pages hold only old rows
        #expect(try b.store.all().count == 6)
    }

    @Test func syncWhileRunningWaitsForCompletion() async throws {
        let a = try device("A")
        try a.store.add(expression: "1+1", result: "2")
        let store = a.store, clock = clock
        await remote.setOnPush {
            await MainActor.run {
                let e = try! store.recent(limit: 1).first!
                guard !e.pinned else { return }
                clock.advance()
                try! store.setPinned(e, true)  // edit mid-push: only a second round can push it
            }
        }
        let engine = a.engine
        let first = Task { await engine.sync() }
        while engine.status != .syncing { await Task.yield() }
        await engine.sync()
        #expect(try a.store.pendingCount() == 0)
        #expect(engine.status == .idle)
        await first.value
    }

    @Test func cursorPersistsAcrossEngines() async throws {
        let a = try device("A"), b = try device("B")
        try a.store.add(expression: "1+1", result: "2")
        await a.engine.sync()
        await b.engine.sync()
        let saved = b.defaults.double(forKey: "cursor")
        #expect(saved > 0)

        let before = await remote.pullFroms.count
        let b2 = SyncEngine(store: b.store, remote: remote, cursorKey: "cursor", defaults: b.defaults)
        await b2.sync()
        #expect(await remote.pullFroms[before] == Date(timeIntervalSince1970: saved - 60))
    }

    @Test func secondSyncPushesNothing() async throws {
        let a = try device("A")
        try a.store.add(expression: "1+1", result: "2")
        await a.engine.sync()
        let pushes = await remote.pushCount
        #expect(pushes == 1)
        await a.engine.sync()
        #expect(await remote.pushCount == pushes)
    }

    @Test func concurrentSyncCallsDoNotOverlap() async throws {
        let a = try device("A")
        try a.store.add(expression: "1+1", result: "2")
        await remote.setOnPush { try? await Task.sleep(for: .milliseconds(50)) }
        let engine = a.engine
        async let first: Void = engine.sync()
        async let second: Void = engine.sync()
        _ = await (first, second)
        #expect(await remote.maxInFlight == 1)
        #expect(await remote.pushCount == 1)
        #expect(await remote.rowCount() == 1)
        #expect(try a.store.pendingCount() == 0)
    }
}
