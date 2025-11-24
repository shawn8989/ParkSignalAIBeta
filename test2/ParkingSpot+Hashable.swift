import Foundation

extension ParkingSpot: Hashable {
    public static func == (lhs: ParkingSpot, rhs: ParkingSpot) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
