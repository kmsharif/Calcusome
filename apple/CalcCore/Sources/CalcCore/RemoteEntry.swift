import Foundation

/// A history row as the server stores it. Dates are encoded by the caller's strategy (ISO 8601 with milliseconds).
public struct RemoteEntry: Codable, Sendable, Equatable {
    public var id: UUID
    public var userID: UUID
    public var deviceID: String
    public var expression: String
    public var result: String
    public var label: String?
    public var pinned: Bool
    public var tapeID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    /// Server-set sync cursor; never sent.
    public var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, expression, result, label, pinned
        case userID = "user_id", deviceID = "device_id", tapeID = "tape_id"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at", syncedAt = "synced_at"
    }

    /// Traps if the entry has no `userID` and no fallback: signed-out rows must never reach the wire.
    init(_ entry: HistoryEntry, fallbackUserID: UUID? = nil) {
        guard let userID = entry.userID ?? fallbackUserID else { preconditionFailure("signed-out entry has no user") }
        id = entry.id
        self.userID = userID
        deviceID = entry.deviceID
        expression = entry.expression
        result = entry.result
        label = entry.label
        pinned = entry.pinned
        tapeID = entry.tapeID
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
    }

    /// Explicit nulls: PostgREST leaves an omitted column unchanged, so a cleared label would never reach the server.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(expression, forKey: .expression)
        try c.encode(result, forKey: .result)
        try c.encode(label, forKey: .label)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(tapeID, forKey: .tapeID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }

    /// The server's merge rule (`history_merge` trigger), which this must match exactly: strictly newer
    /// `updatedAt` takes the incoming content, otherwise the existing content stays; `deletedAt` is the earlier
    /// non-nil of the two; id, user, device and creation time always come from `existing`.
    public static func merged(existing: RemoteEntry, incoming: RemoteEntry) -> RemoteEntry {
        var m = existing
        if incoming.updatedAt > existing.updatedAt {
            m.expression = incoming.expression
            m.result = incoming.result
            m.label = incoming.label
            m.pinned = incoming.pinned
            m.tapeID = incoming.tapeID
            m.updatedAt = incoming.updatedAt
        }
        m.deletedAt = [existing.deletedAt, incoming.deletedAt].compactMap { $0 }.min()
        return m
    }
}
