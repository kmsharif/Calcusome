import Foundation
import SwiftData

/// Local history. Deletes are tombstones so they can reach other devices once sync lands.
@MainActor public final class HistoryStore {
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
        try context.save()
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

    private func touch(_ entry: HistoryEntry) throws {
        entry.updatedAt = now()
        try context.save()
    }

    private func live() -> FetchDescriptor<HistoryEntry> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }
}
