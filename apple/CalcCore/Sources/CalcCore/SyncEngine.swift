import Foundation
import Observation

/// The server side of history sync. Implemented over Supabase in the app target.
public protocol HistoryRemote: Sendable {
    func push(_ entries: [RemoteEntry]) async throws
    /// Rows with `syncedAt >= cursor`, ascending by `syncedAt`, at most `limit` (the server may return fewer).
    func pull(from cursor: Date?, limit: Int) async throws -> [RemoteEntry]
}

/// Pushes dirty rows, then pulls everything newer than the saved server cursor.
@MainActor @Observable public final class SyncEngine {
    public enum Status: Equatable { case idle, syncing, failed(String) }

    public private(set) var status = Status.idle
    public private(set) var lastSynced: Date?

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let remote: any HistoryRemote
    @ObservationIgnored private let cursorKey: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var running = false
    @ObservationIgnored private var rerun = false
    @ObservationIgnored private var scheduled: Task<Void, Never>?

    private static let pushBatch = 500
    private static let pullPage = 1000
    private static let overlap: TimeInterval = 60

    public init(store: HistoryStore, remote: any HistoryRemote, cursorKey: String, defaults: UserDefaults = .standard) {
        self.store = store
        self.remote = remote
        self.cursorKey = cursorKey
        self.defaults = defaults
    }

    /// Debounced: a newer call replaces a pending one. The task holds the engine weakly, so it never outlives its owner.
    public func scheduleSync(after delay: Duration = .seconds(1)) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            scheduled = nil  // a running sync must not be cancelled by a later scheduleSync
            await sync()
        }
    }

    /// Never throws; failures land in `status`. A call during a running sync asks it to go round again.
    public func sync() async {
        if running {
            rerun = true
            return
        }
        running = true
        defer { running = false }
        status = .syncing
        do {
            repeat {
                rerun = false
                try await pushPending()
                try await pullNewer()
            } while rerun
            status = .idle
            lastSynced = .now
        } catch {
            status = .failed(error.localizedDescription)
            // ponytail: fixed 30s retry, add backoff if a dead server sees request storms
            scheduleSync(after: .seconds(30))
        }
    }

    private func pushPending() async throws {
        var pushed = Set<UUID>()  // a row edited mid-push stays dirty; don't push it again this round
        while true {
            let batch = try store.pendingPush(limit: Self.pushBatch).filter { !pushed.contains($0.id) }
            if batch.isEmpty { return }
            try await remote.push(batch)
            try store.markPushed(batch)
            pushed.formUnion(batch.map(\.id))
        }
    }

    private func pullNewer() async throws {
        var cursor = defaults.object(forKey: cursorKey) == nil ? nil : Date(timeIntervalSince1970: defaults.double(forKey: cursorKey))
        var from = cursor.map { $0 - Self.overlap }
        while true {
            let page = try await remote.pull(from: from, limit: Self.pullPage)
            try store.apply(page)
            guard let newest = page.compactMap(\.syncedAt).max(), newest > cursor ?? .distantPast else { return }
            cursor = newest
            defaults.set(newest.timeIntervalSince1970, forKey: cursorKey)
            from = newest
        }
    }
}
