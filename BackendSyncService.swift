import Foundation
import SwiftData

/// BackendSyncService
/// A protocol that abstracts uploading scans and their derived restrictions to a backend.
/// Current implementation is a local stub that logs calls and stores them in memory for debugging.
///
/// Swap the implementation with a real network client in the future without changing call sites.
protocol BackendSyncService {
    func uploadScan(_ scan: SignScan) async throws
    func uploadRestrictions(for scan: SignScan, restrictions: [Restriction]) async throws
}

/// LocalStubBackendSyncService
/// - No real network calls; prints to console and stores last calls in memory.
/// - Useful for development and to validate integration points.
final class LocalStubBackendSyncService: BackendSyncService {
    static let shared = LocalStubBackendSyncService()
    private init() {}

    // Debug memory store
    private(set) var uploadedScanIDs: [UUID] = []
    private(set) var uploadedRestrictionIDs: [UUID] = []

    func uploadScan(_ scan: SignScan) async throws {
        print("[BackendStub] uploadScan id=\(scan.id) text=\(scan.ocrText.prefix(60))… at=\(scan.createdAt)")
        uploadedScanIDs.append(scan.id)
    }

    func uploadRestrictions(for scan: SignScan, restrictions: [Restriction]) async throws {
        let ids = restrictions.map { $0.id }
        print("[BackendStub] uploadRestrictions scan=\(scan.id) restrictions=\(ids)")
        uploadedRestrictionIDs.append(contentsOf: ids)
    }
}
