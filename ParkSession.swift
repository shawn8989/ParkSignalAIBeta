import Foundation
import SwiftData

@Model
final class ParkSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?

    init(startedAt: Date = Date(), endedAt: Date? = nil) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
}
