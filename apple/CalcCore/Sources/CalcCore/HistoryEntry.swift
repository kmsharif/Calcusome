import Foundation
import SwiftData

/// One calculation. Fields mirror the sync table in the product plan so Phase 3 needs no migration.
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

    public init(deviceID: String, expression: String, result: String, at now: Date) {
        id = UUID()
        self.deviceID = deviceID
        self.expression = expression
        self.result = result
        pinned = false
        createdAt = now
        updatedAt = now
    }
}
