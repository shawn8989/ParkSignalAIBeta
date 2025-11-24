import Foundation
import SwiftData

extension Car {
    var activeSession: ParkSession? {
        sessions.first { $0.endedAt == nil }
    }

    var isParked: Bool { activeSession != nil }

    @discardableResult
    func startParking(at spot: ParkingSpot, now: Date = .now, in context: ModelContext) -> ParkSession {
        // End any existing active session for this car (across all spots)
        if let current = activeSession {
            current.endedAt = now
        }
        let session = ParkSession(spot: spot, startedAt: now, endedAt: nil, car: self)
        // Link both sides
        spot.parkSessions.append(session)
        sessions.append(session)
        // Persist
        context.insert(session)
        return session
    }

    func endCurrentParking(at date: Date = .now) {
        activeSession?.endedAt = date
    }

    @discardableResult
    func toggleParking(at spot: ParkingSpot, now: Date = .now, in context: ModelContext) -> ParkSession? {
        if let current = activeSession {
            // If already parked at this spot, end it; otherwise, switch to the new spot
            if current.spot?.id == spot.id {
                current.endedAt = now
                return nil
            } else {
                current.endedAt = now
                return startParking(at: spot, now: now, in: context)
            }
        } else {
            return startParking(at: spot, now: now, in: context)
        }
    }
}
