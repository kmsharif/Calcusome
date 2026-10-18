import CalcCore
import Foundation
import Supabase

/// `HistoryRemote` over PostgREST. Row-level security scopes every call to the signed-in user.
struct SupabaseHistoryRemote: HistoryRemote {
    let client: SupabaseClient

    /// The server's merge trigger drops stale rows, so the response can be short: don't ask for it back.
    func push(_ entries: [RemoteEntry]) async throws {
        try await client.from("history_entries").upsert(entries, onConflict: "id", returning: .minimal).execute()
    }

    func pull(from cursor: Date?, limit: Int) async throws -> [RemoteEntry] {
        var query = client.from("history_entries").select()
        if let cursor { query = query.gte("synced_at", value: cursor) }
        return try await query.order("synced_at").limit(limit).execute().value
    }
}

/// ISO 8601 with milliseconds, both ways. The SDK's default coder cuts the last digit instead of rounding, so about
/// half of `HistoryStore`'s whole-millisecond dates would come back 1 ms early and look dirty forever.
/// Decoded dates are whole milliseconds (the server's microseconds are dropped); the 60 s pull overlap absorbs that.
/// `ISO8601DateFormatter` is thread-safe once configured (Foundation docs); it just isn't marked `Sendable`.
nonisolated(unsafe) private let fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
nonisolated(unsafe) private let whole = ISO8601DateFormatter()  // Postgres omits a zero fraction

extension JSONEncoder {
    static let history: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(fractional.string(from: date))
        }
        return e
    }()
}

extension JSONDecoder {
    static let history: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = fractional.date(from: s) ?? whole.date(from: s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
            }
            return date
        }
        return d
    }()
}
