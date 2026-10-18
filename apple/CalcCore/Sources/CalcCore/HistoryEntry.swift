import Foundation
import SwiftData

/// One calculation. Fields mirror the sync table (`RemoteEntry`); `needsPush` is local only and never sent.
@Model public final class HistoryEntry {
    @Attribute(.unique) public var id: UUID
    public var userID: UUID?
    public var deviceID: String
    public var expression: String
    public var result: String
    public var label: String?
    public var pinned: Bool
    public var tapeID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    /// Changed locally since the last confirmed push. The default lets SwiftData add the column to existing stores.
    public var needsPush: Bool = true

    public init(deviceID: String, expression: String, result: String, at now: Date) {
        id = UUID()
        self.deviceID = deviceID
        self.expression = expression
        self.result = result
        pinned = false
        createdAt = now
        updatedAt = now
    }

    convenience init(_ remote: RemoteEntry) {
        self.init(deviceID: remote.deviceID, expression: remote.expression, result: remote.result, at: remote.createdAt)
        id = remote.id
        apply(remote)
        needsPush = false
    }

    /// Copies every synced field except `id`.
    func apply(_ remote: RemoteEntry) {
        userID = remote.userID
        deviceID = remote.deviceID
        expression = remote.expression
        result = remote.result
        label = remote.label
        pinned = remote.pinned
        tapeID = remote.tapeID
        createdAt = remote.createdAt
        updatedAt = remote.updatedAt
        deletedAt = remote.deletedAt
    }
}
