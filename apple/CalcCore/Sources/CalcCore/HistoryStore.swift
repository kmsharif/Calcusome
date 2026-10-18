import Foundation
import Observation
import SwiftData

/// Local history. Deletes are tombstones so they can reach other devices once sync lands.
@MainActor @Observable public final class HistoryStore {
    /// Bumped on every save, so views in every window can refresh.
    public private(set) var revision = 0

    let context: ModelContext
    private let container: ModelContainer  // the context traps if its container is released
    private let deviceID: String
    private let now: () -> Date

    public init(container: ModelContainer, deviceID: String, now: @escaping () -> Date = Date.init) {
        self.container = container
        context = container.mainContext
        self.deviceID = deviceID
        self.now = now
    }

    public static func inMemory(deviceID: String = "test", now: @escaping () -> Date = Date.init) throws -> HistoryStore {
        let container = try ModelContainer(for: HistoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return HistoryStore(container: container, deviceID: deviceID, now: now)
    }

    @discardableResult
    public func add(expression: String, result: String) throws -> HistoryEntry {
        let entry = HistoryEntry(deviceID: deviceID, expression: expression, result: result, at: now())
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
        try save()
    }

    private func save() throws {
        try context.save()
        revision += 1
    }

    private func live() -> FetchDescriptor<HistoryEntry> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }
}
