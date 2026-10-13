import Foundation
import SwiftData
import Combine
import CloudKit
import CoreData

@MainActor
final class AppIssueStore: ObservableObject {
    static let shared = AppIssueStore()
    @Published var message: String?
}

@MainActor
final class StorageStatus: ObservableObject {
    static let shared = StorageStatus()
    @Published var summary = "Stored on this device"
    @Published var detail = "iCloud sync has not been verified."
    var usesCloudStore = false
    var localOnlyReason = "iCloud storage could not be opened. Your saved data remains on this device; sync is unavailable."

    func refreshAccount() async {
        guard usesCloudStore else {
            summary = "Local storage only"
            detail = localOnlyReason
            return
        }
        do {
            let status = try await CKContainer(identifier: "iCloud.com.SOTech.ParkSignalAI").accountStatus()
            if status == .available {
                summary = "iCloud available"
                detail = "Sync is configured. Availability does not confirm that all data has uploaded. Verify your spots and photos on another device."
            } else {
                summary = "Saved locally — iCloud unavailable"
                detail = "Sign into iCloud in device Settings and enable iCloud for ParkSignal to sync your data."
            }
        } catch {
            summary = "Saved locally — iCloud unavailable"
            detail = "iCloud couldn't be reached. Your local data is still available. Try again when connected."
        }
    }
    func handleCloudEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
              event.endDate != nil else { return }
        if !event.succeeded {
            summary = "iCloud sync needs attention"
            detail = "A sync operation failed. Your local data is available; check iCloud access, connectivity and available storage."
        } else if event.type == .export || event.type == .import {
            summary = "iCloud transfer completed"
            detail = "The latest transfer completed. Changes may take time to appear on other devices."
        }
    }
}

@MainActor
extension ModelContext {
    @discardableResult
    func saveOrReport() -> Bool {
        do { try save(); return true }
        catch {
            rollback()
            AppIssueStore.shared.message = "Couldn’t save changes: \(error.localizedDescription)"
            return false
        }
    }
}
