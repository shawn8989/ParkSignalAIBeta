import Foundation
import SwiftData

/// A user's proposed edits are values until Save is pressed. Cancelling review
/// never replaces the saved rules or changes the device's reminders.
struct ReviewedRestriction {
    var type: RestrictionType
    var days: [Int]
    var start: Date
    var end: Date
    var durationMinutes: Int?
    var needsReview: Bool
    var reviewReasons: [String]
}

struct ScanReviewService {
    let context: ModelContext

    func save(_ drafts: [ReviewedRestriction], for spot: ParkingSpot, scan: SignScan?,
              text: String, photoFilename: String?, sourceUser: UUID, sourceRequiresReview: Bool = false) throws -> [Restriction] {
        // Replace only this scan's rules. Other signs on the same curb remain intact.
        let old = scan?.restrictionsList ?? []
        for rule in old { context.delete(rule) }
        let created = drafts.map { draft in
            Restriction(type: draft.type, startTime: draft.start, endTime: draft.end,
                        daysOfWeek: draft.days, sourceUser: sourceUser,
                        signPhotoFilename: photoFilename, ocrText: text, spot: spot, scan: scan,
                        needsReview: sourceRequiresReview || draft.needsReview || draft.type == .other, reviewReasons: draft.reviewReasons,
                        durationMinutes: draft.durationMinutes)
        }
        for rule in created {
            context.insert(rule)
            if !spot.restrictionsList.contains(where: { $0.id == rule.id }) { spot.restrictionsList.append(rule) }
        }
        if let scan {
            scan.restrictionsList = created
            scan.needsReview = created.isEmpty || created.contains(where: \.needsReview)
            scan.status = scan.needsReview ? "needsReview" : "complete"
            scan.analyzedAt = Date()
            scan.mergedOCRText = text
            scan.aiAnalysisText = nil
            scan.localAnalysisText = nil
            scan.signalState = scan.needsReview ? "gray" : ParkingSignalEvaluator.status(for: created).rawValue
            spot.updateLastScan(from: scan)
        }
        do {
            try context.save()
            return created
        } catch {
            context.rollback()
            throw error
        }
    }
}
