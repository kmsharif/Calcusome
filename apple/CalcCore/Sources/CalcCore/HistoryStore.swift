import Foundation
import Observation
import SwiftData

/// Local history. Deletes are tombstones so they can reach other devices.
@MainActor @Observable public final class HistoryStore {
    /// Bumped on every save, so views in every window can refresh.
    public private(set) var revision = 0

    let context: ModelContext
    private let container: ModelContainer  // the context traps if its container is released
    private let deviceID: String
    private let now: () -> Date

    /// Signed-in account; new entries are stamped with it. Nil while signed out.
    public var userID: UUID?
    /// Fired after every local mutation (not after `apply`), so the sync engine can schedule a push.
    public var onLocalChange: (() -> Void)?

    public init(container: ModelContainer, deviceID: String, now: @escaping () -> Date = Date.init) {
        self.container = container
        context = container.mainContext
        self.deviceID = deviceID
        // Whole milliseconds survive a trip through ISO 8601 JSON unchanged.
        self.now = { Date(timeIntervalSince1970: (now().timeIntervalSince1970 * 1000).rounded(.down) / 1000) }
    }

    public static func inMemory(deviceID: String = "test", now: @escaping () -> Date = Date.init) throws -> HistoryStore {
        let container = try ModelContainer(for: HistoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return HistoryStore(container: container, deviceID: deviceID, now: now)
    }

    @discardableResult
    public func add(expression: String, result: String) throws -> HistoryEntry {
        let entry = HistoryEntry(deviceID: deviceID, expression: expression, result: result, at: now())
        entry.userID = userID
        context.insert(entry)
        try save()
        return entry
    }

    /// Live entries, newest first.
    public func recent(limit: Int) throws -> [HistoryEntry] {
        var descriptor = live()
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Live entries, pinned first, then newest.
    public func all() throws -> [HistoryEntry] {
        let entries = try context.fetch(live())
        return entries.filter(\.pinned) + entries.filter { !$0.pinned }
    }

    public func search(_ text: String, locale: Locale = .current) throws -> [HistoryEntry] {
        // ponytail: in-memory filter over all live rows; move into the predicate if history grows past ~10k.
        // Expressions are canonical, so match them against the canonical query; labels are free text.
        let canonical = InputNormalizer.normalize(text, locale: locale)
        return try all().filter {
            $0.expression.localizedStandardContains(canonical) || ($0.label?.localizedStandardContains(text) ?? false)
        }
    }

    public func setPinned(_ entry: HistoryEntry, _ pinned: Bool) throws {
        entry.pinned = pinned
        try touch(entry)
    }

    public func setLabel(_ entry: HistoryEntry, _ label: String?) throws {
        entry.label = (label?.isEmpty ?? true) ? nil : label
        try touch(entry)
    }

    public func delete(_ entry: HistoryEntry) throws {
        entry.deletedAt = now()
        try touch(entry)
    }

    /// Tombstones live, unbookmarked entries created before `cutoff`. Clear History passes now.
    @discardableResult
    public func deleteUnpinned(before cutoff: Date) throws -> Int {
        let old = try context.fetch(live()).filter { !$0.pinned && $0.createdAt < cutoff }
        guard !old.isEmpty else { return 0 }
        let stamp = now()
        for entry in old {
            entry.deletedAt = stamp
            entry.updatedAt = stamp
            entry.needsPush = true
        }
        try save()
        return old.count
    }

    /// Live entries as RFC 4180 CSV, newest first.
    public func exportCSV() throws -> String {
        let dates = ISO8601DateFormatter()
        let rows = try context.fetch(live()).map { e in
            [dates.string(from: e.createdAt), e.label ?? "", e.expression, e.result, e.pinned ? "yes" : "no"]
                .map(Self.csvField).joined(separator: ",")
        }
        return (["date,label,expression,result,bookmarked"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ s: String) -> String {
        s.contains(where: { ",\"\r\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    private func touch(_ entry: HistoryEntry) throws {
        entry.updatedAt = now()
        entry.needsPush = true
        try save()
    }

    private func save(local: Bool = true) throws {
        try context.save()
        revision += 1
        if local { onLocalChange?() }
    }

    // MARK: Sync

    /// Dirty rows of the signed-in account, oldest edit first.
    public func pendingPush(limit: Int) throws -> [RemoteEntry] {
        var descriptor = pending()
        descriptor.sortBy = [SortDescriptor(\.updatedAt)]
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map { RemoteEntry($0) }
    }

    public func pendingCount() throws -> Int { try context.fetchCount(pending()) }

    /// Clears `needsPush` only where the row still matches the pushed snapshot, so edits made mid-push stay pending.
    public func markPushed(_ pushed: [RemoteEntry]) throws {
        let byID = Dictionary(pushed.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>()) {
            guard let p = byID[entry.id], entry.updatedAt == p.updatedAt, entry.deletedAt == p.deletedAt else { continue }
            entry.needsPush = false
        }
        try save(local: false)
    }

    /// Merges server rows into the local store with the server's rule. Rows where local wins stay (or become) dirty.
    /// Rows of any other account (all of them while signed out) are ignored: a pull that lands after sign-out must not
    /// bring back what `purge` removed.
    public func apply(_ remote: [RemoteEntry]) throws {
        // ponytail: one fetch of every row; index by id in the predicate if history grows past ~10k.
        var local = Dictionary(try context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for r in remote where r.userID == userID {
            if let entry = local[r.id] {
                var m = RemoteEntry.merged(existing: RemoteEntry(entry, fallbackUserID: r.userID), incoming: r)
                m.syncedAt = r.syncedAt
                entry.apply(m)
                entry.needsPush = m != r
            } else {
                let entry = HistoryEntry(r)
                context.insert(entry)
                local[r.id] = entry
            }
        }
        try save(local: false)
    }

    /// Signs in: claims every signed-out entry for `userID` and queues it for push.
    public func adopt(userID: UUID) throws {
        self.userID = userID
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.userID == nil })) {
            entry.userID = userID
            entry.needsPush = true
        }
        try save()
    }

    /// Signs out: really deletes that account's rows from this device (the server keeps them).
    public func purge(userID: UUID) throws {
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.userID == userID })) {
            context.delete(entry)
        }
        self.userID = nil
        try save(local: false)
    }

    private func pending() -> FetchDescriptor<HistoryEntry> {
        FetchDescriptor(predicate: #Predicate { $0.needsPush && $0.userID != nil })
    }

    private func live() -> FetchDescriptor<HistoryEntry> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }
}
