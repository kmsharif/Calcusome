import Foundation
import SwiftData
import Testing
@testable import CalcCore

@MainActor final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance() { now += 60 }
}

@MainActor struct HistoryStoreTests {
    let clock = TestClock()
    let store: HistoryStore

    init() throws {
        let clock = clock
        store = try HistoryStore.inMemory(deviceID: "test", now: { clock.now })
    }

    @Test func addSetsFields() throws {
        let e = try store.add(expression: "500×64", result: "32000")
        #expect(e.deviceID == "test")
        #expect(e.userID == nil)
        #expect(e.pinned == false)
        #expect(e.createdAt == clock.now)
        #expect(e.updatedAt == clock.now)
        #expect(e.deletedAt == nil)
    }

    @Test func recentNewestFirst() throws {
        try store.add(expression: "1+1", result: "2"); clock.advance()
        try store.add(expression: "1+2", result: "3"); clock.advance()
        try store.add(expression: "1+3", result: "4")
        #expect(try store.recent(limit: 2).map(\.result) == ["4", "3"])
    }

    @Test func pinnedFirst() throws {
        let oldest = try store.add(expression: "1+1", result: "2"); clock.advance()
        try store.add(expression: "1+2", result: "3")
        try store.setPinned(oldest, true)
        #expect(try store.all().first?.id == oldest.id)
    }

    @Test func searchMatchesLabelAndExpression() throws {
        let rent = try store.add(expression: "1200÷3", result: "400")
        try store.setLabel(rent, "Rent split")
        try store.add(expression: "500×64", result: "32000")
        #expect(try store.search("rent").map(\.id) == [rent.id])
        #expect(try store.search("500").map(\.result) == ["32000"])
    }

    @Test func emptyLabelStoredAsNil() throws {
        let e = try store.add(expression: "1+1", result: "2")
        try store.setLabel(e, "")
        #expect(e.label == nil)
    }

    @Test func mutationsBumpUpdatedAt() throws {
        let e = try store.add(expression: "1+1", result: "2")
        let created = clock.now
        clock.advance(); try store.setLabel(e, "x")
        #expect(e.updatedAt == clock.now)
        clock.advance(); try store.setPinned(e, true)
        #expect(e.updatedAt == clock.now)
        clock.advance(); try store.delete(e)
        #expect(e.updatedAt == clock.now)
        #expect(e.createdAt == created)
    }

    @Test func deleteIsTombstone() throws {
        let e = try store.add(expression: "1+1", result: "2")
        try store.setLabel(e, "gone")
        try store.delete(e)
        #expect(try store.recent(limit: 10).isEmpty)
        #expect(try store.all().isEmpty)
        #expect(try store.search("gone").isEmpty)
        let raw = try store.context.fetch(FetchDescriptor<HistoryEntry>())
        #expect(raw.count == 1)
        #expect(raw.first?.deletedAt != nil)
    }

    @Test func deviceIDStable() {
        let defaults = UserDefaults(suiteName: "deviceIDStable-\(UUID())")!
        let first = DeviceID.current(defaults)
        #expect(!first.isEmpty)
        #expect(DeviceID.current(defaults) == first)
    }
}
