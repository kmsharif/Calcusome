import Foundation
import SwiftData
import Testing
@testable import CalcCore

@MainActor struct HistorySyncTests {
    let clock = TestClock()
    let store: HistoryStore
    let u = UUID()
    let v = UUID()
    let t1 = Date(timeIntervalSince1970: 1_000_000)
    var t2: Date { t1 + 60 }
    var t3: Date { t1 + 120 }

    init() throws {
        let clock = clock
        store = try HistoryStore.inMemory(deviceID: "test", now: { clock.now })
    }

    func remote(_ e: HistoryEntry, _ edit: (inout RemoteEntry) -> Void = { _ in }) -> RemoteEntry {
        var r = RemoteEntry(e, fallbackUserID: u)
        edit(&r)
        return r
    }

    func rawEntries() throws -> [HistoryEntry] { try store.context.fetch(FetchDescriptor<HistoryEntry>()) }

    @Test func addStampsUserIDWhenSignedIn() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        #expect(e.userID == u)
        #expect(e.needsPush)
    }

    @Test func timestampsAreWholeMilliseconds() throws {
        clock.now = Date(timeIntervalSince1970: 1_000_000.123456)
        let e = try store.add(expression: "1+1", result: "2")
        #expect(e.createdAt == Date(timeIntervalSince1970: 1_000_000.123))
        #expect(e.updatedAt == e.createdAt)
    }

    @Test func remoteEntryJSONRoundTrip() throws {
        store.userID = u
        clock.now = Date(timeIntervalSince1970: 1_000_000.123456)
        let e = try store.add(expression: "1+1", result: "2")
        let original = RemoteEntry(e)
        let data = try Wire.encoder.encode(original)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"user_id\""))
        #expect(json.contains("\"label\":null"))
        #expect(json.contains("\"tape_id\":null"))
        #expect(json.contains("\"deleted_at\":null"))
        #expect(!json.contains("synced_at"))
        #expect(try Wire.decoder.decode(RemoteEntry.self, from: data) == original)
    }

    @Test func mergeNewerWins() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let existing = remote(e) { $0.label = "a"; $0.updatedAt = t1 }
        let incoming = remote(e) { $0.label = "b"; $0.updatedAt = t2 }
        let m = RemoteEntry.merged(existing: existing, incoming: incoming)
        #expect(m.label == "b")
        #expect(m.updatedAt == t2)
    }

    @Test func mergeTieKeepsExisting() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let existing = remote(e) { $0.label = "a"; $0.updatedAt = t1 }
        let incoming = remote(e) { $0.label = "b"; $0.updatedAt = t1 }
        #expect(RemoteEntry.merged(existing: existing, incoming: incoming).label == "a")
    }

    @Test func mergeTombstoneSticky() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let existing = remote(e) { $0.updatedAt = t1; $0.deletedAt = t1 }
        let incoming = remote(e) { $0.updatedAt = t2; $0.label = "b" }
        let m = RemoteEntry.merged(existing: existing, incoming: incoming)
        #expect(m.deletedAt == t1)
        #expect(m.label == "b")
    }

    @Test func mergeOlderTombstoneWins() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let existing = remote(e) { $0.updatedAt = t2; $0.label = "a" }
        let incoming = remote(e) { $0.updatedAt = t1; $0.deletedAt = t1; $0.label = "b" }
        let m = RemoteEntry.merged(existing: existing, incoming: incoming)
        #expect(m.deletedAt == t1)
        #expect(m.updatedAt == t2)
        #expect(m.label == "a")
    }

    @Test func mergeStaleEarlierTombstoneWins() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let existing = remote(e) { $0.updatedAt = t2; $0.deletedAt = t2; $0.label = "a" }
        let incoming = remote(e) { $0.updatedAt = t1; $0.deletedAt = t1; $0.label = "b" }
        let m = RemoteEntry.merged(existing: existing, incoming: incoming)
        #expect(m.deletedAt == t1)
        #expect(m.updatedAt == t2)
        #expect(m.label == "a")
    }

    @Test func mergeKeepsIdentity() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let existing = remote(e)
        let incoming = remote(e) { $0.deviceID = "other"; $0.createdAt = t3; $0.userID = v; $0.updatedAt = t2 }
        let m = RemoteEntry.merged(existing: existing, incoming: incoming)
        #expect(m.deviceID == existing.deviceID)
        #expect(m.createdAt == existing.createdAt)
        #expect(m.userID == existing.userID)
    }

    @Test func pendingPushOnlySignedInDirtyRows() throws {
        try store.add(expression: "1+1", result: "2")
        #expect(try store.pendingPush(limit: 10).isEmpty)
        store.userID = u
        let e = try store.add(expression: "2+2", result: "4")
        let pending = try store.pendingPush(limit: 10)
        #expect(pending.map(\.id) == [e.id])
        #expect(pending.first?.userID == u)
        try store.markPushed(pending)
        #expect(try store.pendingPush(limit: 10).isEmpty)
    }

    @Test func markPushedSkipsRowsEditedSince() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        let snapshot = try store.pendingPush(limit: 10)
        clock.advance()
        try store.setPinned(e, true)
        try store.markPushed(snapshot)
        #expect(e.needsPush)
        #expect(try store.pendingPush(limit: 10).map(\.pinned) == [true])
    }

    @Test func applyInsertsUnknown() throws {
        store.userID = u
        let r = RemoteEntry(HistoryEntry(deviceID: "other", expression: "3+3", result: "6", at: t1), fallbackUserID: u)
        try store.apply([r])
        let all = try store.all()
        #expect(all.map(\.id) == [r.id])
        #expect(all.first?.needsPush == false)
    }

    @Test func applyNewerRemoteWins() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        try store.setLabel(e, "a")
        try store.markPushed(try store.pendingPush(limit: 10))
        let r = remote(e) { $0.label = "b"; $0.updatedAt = t3 }
        try store.apply([r])
        #expect(e.label == "b")
        #expect(e.updatedAt == t3)
        #expect(!e.needsPush)
    }

    @Test func applyOlderRemoteKeepsLocalAndRepushes() throws {
        store.userID = u
        clock.now = t2
        let e = try store.add(expression: "1+1", result: "2")
        try store.setLabel(e, "local")
        let stamp = e.updatedAt
        let r = remote(e) { $0.label = "stale"; $0.updatedAt = t1 }
        try store.apply([r])
        #expect(e.label == "local")
        #expect(e.updatedAt == stamp)
        #expect(e.needsPush)
    }

    @Test func applyRemoteDeleteHidesEntry() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        try store.setLabel(e, "gone")
        try store.markPushed(try store.pendingPush(limit: 10))
        try store.apply([remote(e) { $0.updatedAt = t3; $0.deletedAt = t3 }])
        #expect(try store.recent(limit: 10).isEmpty)
        #expect(try store.all().isEmpty)
        #expect(try store.search("gone").isEmpty)
        #expect(try rawEntries().count == 1)
    }

    @Test func applyOwnEchoIsNoOp() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        let pushed = try store.pendingPush(limit: 10)
        try store.markPushed(pushed)
        let echo = remote(e) { $0.syncedAt = t3 }
        try store.apply([echo])
        #expect(!e.needsPush)
        #expect(RemoteEntry(e).id == echo.id)
        #expect(RemoteEntry(e) == { var r = echo; r.syncedAt = nil; return r }())
    }

    @Test func applyDoesNotFireOnLocalChange() throws {
        var fired = 0
        store.onLocalChange = { fired += 1 }
        let e = try store.add(expression: "1+1", result: "2")
        #expect(fired == 1)
        store.userID = u
        try store.apply([remote(e) { $0.label = "b"; $0.updatedAt = t3 }])
        #expect(fired == 1)
    }

    @Test func applyBumpsRevision() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        let before = store.revision
        try store.apply([remote(e)])
        #expect(store.revision == before + 1)
    }

    @Test func applyIgnoresOtherAccountRows() throws {
        let theirs = RemoteEntry(HistoryEntry(deviceID: "other", expression: "3+3", result: "6", at: t1), fallbackUserID: v)
        try store.apply([theirs])  // signed out: nothing applies
        store.userID = u
        try store.apply([theirs])
        #expect(try rawEntries().isEmpty)
    }

    @Test func adoptClaimsLocalEntries() throws {
        let a = try store.add(expression: "1+1", result: "2")
        let b = try store.add(expression: "2+2", result: "4")
        try store.delete(b)
        try store.adopt(userID: u)
        #expect(store.userID == u)
        #expect(a.userID == u && b.userID == u)
        #expect(a.needsPush && b.needsPush)
    }

    @Test func purgeRemovesOnlyThatAccount() throws {
        try store.add(expression: "0+0", result: "0")
        store.userID = u
        try store.add(expression: "1+1", result: "2")
        store.userID = v
        let kept = try store.add(expression: "2+2", result: "4")
        try store.purge(userID: u, keepUnsynced: false)
        #expect(store.userID == nil)
        let rest = try rawEntries()
        #expect(rest.count == 2)
        #expect(rest.contains { $0.id == kept.id })
        #expect(rest.contains { $0.userID == nil })
        #expect(!rest.contains { $0.userID == u })
    }

    @Test func pendingCountIgnoresSignedOutRows() throws {
        try store.add(expression: "1+1", result: "2")
        #expect(try store.pendingCount() == 0)
        store.userID = u
        try store.add(expression: "2+2", result: "4")
        #expect(try store.pendingCount() == 1)
    }

    @Test func purgeKeepsUnsyncedWhenAsked() throws {
        store.userID = u
        let synced = try store.add(expression: "1+1", result: "2")
        let unsynced = try store.add(expression: "2+2", result: "4")
        try store.markPushed([RemoteEntry(synced)])
        try store.purge(userID: u, keepUnsynced: true)
        let rest = try rawEntries()
        #expect(rest.map(\.id) == [unsynced.id])
        #expect(unsynced.userID == nil)
        #expect(unsynced.needsPush)
    }

    @Test func purgeDiscardsWhenNotAsked() throws {
        store.userID = u
        let synced = try store.add(expression: "1+1", result: "2")
        try store.add(expression: "2+2", result: "4")
        try store.markPushed([RemoteEntry(synced)])
        try store.purge(userID: u, keepUnsynced: false)
        #expect(try rawEntries().isEmpty)
    }

    @Test func overLimitRowsStayLocal() throws {
        store.userID = u
        let ok = try store.add(expression: "1+1", result: "2")
        try store.add(expression: String(repeating: "1", count: 1001), result: "1")
        #expect(try store.pendingPush(limit: 10).map(\.id) == [ok.id])
        #expect(try store.pendingCount() == 1)
    }

    @Test func labelCappedAt200() throws {
        let e = try store.add(expression: "1+1", result: "2")
        try store.setLabel(e, String(repeating: "a", count: 250))
        #expect(e.label?.count == 200)
        // The server counts code points, not characters: a 5-scalar family emoji must not overflow it.
        try store.setLabel(e, String(repeating: "👨‍👩‍👧", count: 50))
        #expect((e.label?.unicodeScalars.count ?? 0) <= 200)
        #expect(e.label?.last == "👨‍👩‍👧")
    }

    @Test func editAfterNewerRemoteStillWins() throws {
        store.userID = u
        let e = try store.add(expression: "1+1", result: "2")
        let r = remote(e) { $0.updatedAt = clock.now + 10 }
        try store.apply([r])
        try store.setPinned(e, true)
        #expect(e.updatedAt > r.updatedAt)
    }
}
